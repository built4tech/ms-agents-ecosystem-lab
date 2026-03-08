# Identidad, Aprobaciones e Identidad Delegada en Multi-Usuario

**Fecha**: 2026-03-08  
**Contexto**: Arquitectura de identidad y seguridad en despliegue multi-usuario

---

## 1. Identidad por Instancia: Aislamiento Completo

### Arquitectura Actual

Cada ejecución del código crea una instancia completamente independiente:

```python
# app/core/agent.py - línea 38
def _get_azure_credential():
    """Devuelve la credencial Azure apropiada para el entorno actual."""
    if is_cloud_runtime():
        return DefaultAzureCredential(exclude_interactive_browser_credential=True)
    else:
        return DefaultAzureCredential(
            exclude_interactive_browser_credential=True,
            exclude_shared_token_cache_credential=True,
        )

# app/core/agent.py - línea 73
class SimpleChatAgent(AgentInterface):
    def __init__(self) -> None:
        self.chat_client: AzureAIClient | None = None
        self.agent: ChatAgent | None = None
        self.agent_thread: AgentThread | None = None
        self._pending_approval: Content | None = None  # ← Estado local
```

### Diagrama de Instancias Independientes

```
Usuario A (Laptop)              Usuario B (Servidor)           Usuario C (Local)
      ↓                                ↓                              ↓
Proceso Python A                Proceso Python B              Proceso Python C
      ↓                                ↓                              ↓
┌──────────────────────┐       ┌──────────────────────┐      ┌──────────────────────┐
│ SimpleChatAgent      │       │ SimpleChatAgent      │      │ SimpleChatAgent      │
│ Instancia A          │       │ Instancia B          │      │ Instancia C          │
├──────────────────────┤       ├──────────────────────┤      ├──────────────────────┤
│ chat_client: Client1 │       │ chat_client: Client2 │      │ chat_client: Client3 │
│ agent: Agent1        │       │ agent: Agent2        │      │ agent: Agent3        │
│ agent_thread: ABC123 │       │ agent_thread: DEF456 │      │ agent_thread: GHI789 │
│ _pending_approval:   │       │ _pending_approval:   │      │ _pending_approval:   │
│   None               │       │   <WeatherRequest>   │      │   None               │
├──────────────────────┤       ├──────────────────────┤      ├──────────────────────┤
│ Credential A         │       │ Credential B         │      │ Credential C         │
│ (Azure CLI)          │       │ (Managed Identity)   │      │ (VS Code)            │
└──────────────────────┘       └──────────────────────┘      └──────────────────────┘
       ↓                                ↓                              ↓
Token JWT único A               Token JWT único B              Token JWT único C
```

### Confirmación: Identidades Distintas

**✅ SÍ, cada instancia tiene identidad completamente separada**:

1. **Credential independiente**:
   ```python
   # Usuario A ejecuta
   credential_a = DefaultAzureCredential()  # Instancia 1
   
   # Usuario B ejecuta (simultáneo)
   credential_b = DefaultAzureCredential()  # Instancia 2
   
   # Son objetos Python completamente diferentes
   credential_a is credential_b  # False
   ```

2. **Token JWT diferente**:
   ```
   Usuario A → Azure CLI login (carlos@company.com)
   Token A: eyJ0eXAi... (sub: carlos@company.com)
   
   Usuario B → Managed Identity (app-service-identity)
   Token B: eyJ0eXAi... (sub: app-service-object-id)
   
   Usuario C → VS Code (ana@company.com)
   Token C: eyJ0eXAi... (sub: ana@company.com)
   ```

3. **Audit trail diferenciado**:
   ```
   Application Insights:
   
   Request 1:
   - Timestamp: 2026-03-08 10:15:23
   - User Principal: carlos@company.com
   - Thread ID: abc123
   - Tool calls: [weather_tool]
   
   Request 2:
   - Timestamp: 2026-03-08 10:15:25
   - User Principal: app-service-managed-identity
   - Thread ID: def456
   - Tool calls: [web_search_tool]
   
   Request 3:
   - Timestamp: 2026-03-08 10:15:27
   - User Principal: ana@company.com
   - Thread ID: ghi789
   - Tool calls: [weather_tool]
   ```

---

## 2. Aprobaciones de Herramientas: Estado Local No Compartido

### Implementación Actual

```python
# app/core/agent.py - línea 76
class SimpleChatAgent(AgentInterface):
    def __init__(self) -> None:
        self._pending_approval: Content | None = None  # ← Variable de INSTANCIA

# app/core/agent.py - línea 151
async def process_user_message(self, message: str) -> str:
    elif self._pending_approval is not None:  # ← Chequea estado LOCAL
        normalized = message.strip().lower()
        if normalized in APPROVAL_YES:
            approval_response = self._pending_approval.to_function_approval_response(approved=True)
            self._pending_approval = None  # ← Limpia estado LOCAL
            # ...
```

### Escenario Multi-Usuario: Aprobaciones Independientes

```
┌─────────────────────────────────────────────────────────────────────────┐
│ LÍNEA DE TIEMPO SIMULTÁNEA                                              │
├─────────────────────────────────────────────────────────────────────────┤
│ T0: 10:15:00                                                            │
│                                                                          │
│ Usuario A ejecuta:                                                      │
│ > "¿Qué tiempo hace en Madrid?"                                        │
│                                                                          │
│ Agente A detecta necesidad de tool: get_weather_by_city                │
│ approval_mode="always_require" → Solicita aprobación                   │
│                                                                          │
│ Instancia A:                                                            │
│   _pending_approval = WeatherToolRequest(ciudad="Madrid")              │
│                                                                          │
│ Asistente A: "Necesito tu aprobación para ejecutar la herramienta      │
│              get_weather_by_city. Responde 'si' para aprobar o         │
│              'no' para cancelar."                                       │
├─────────────────────────────────────────────────────────────────────────┤
│ T1: 10:15:10 (Usuario A NO ha respondido aún)                          │
│                                                                          │
│ Usuario B ejecuta (simultáneo):                                         │
│ > "¿Qué tiempo hace en Barcelona?"                                     │
│                                                                          │
│ Agente B detecta necesidad de tool: get_weather_by_city                │
│ approval_mode="always_require" → Solicita aprobación                   │
│                                                                          │
│ Instancia B:                                                            │
│   _pending_approval = WeatherToolRequest(ciudad="Barcelona")           │
│                                                                          │
│ Asistente B: "Necesito tu aprobación para ejecutar la herramienta..."  │
├─────────────────────────────────────────────────────────────────────────┤
│ T2: 10:15:15                                                            │
│                                                                          │
│ Usuario A responde: "si"                                                │
│                                                                          │
│ Instancia A:                                                            │
│   if normalized in APPROVAL_YES:                                        │
│       approval_response = self._pending_approval.to_function_approval_response(approved=True)
│       self._pending_approval = None  # ← Limpia SOLO instancia A       │
│       # Ejecuta tool con ciudad="Madrid"                               │
│                                                                          │
│ Instancia B:                                                            │
│   _pending_approval = WeatherToolRequest(ciudad="Barcelona")           │
│   ↑ NO AFECTADA, sigue esperando aprobación de Usuario B               │
├─────────────────────────────────────────────────────────────────────────┤
│ T3: 10:15:20                                                            │
│                                                                          │
│ Usuario B responde: "no"                                                │
│                                                                          │
│ Instancia B:                                                            │
│   elif normalized in APPROVAL_NO:                                       │
│       self._pending_approval = None  # ← Limpia SOLO instancia B       │
│       response = "Entendido, no ejecutaré la herramienta."             │
│                                                                          │
│ Instancia A:                                                            │
│   _pending_approval = None  # ← Ya había sido limpiada                 │
│   ↑ NO AFECTADA por la decisión de Usuario B                           │
└─────────────────────────────────────────────────────────────────────────┘
```

### Confirmación: Aprobaciones NO se Heredan

**✅ CORRECTO: Las aprobaciones NO se heredan entre instancias**:

1. **Estado en memoria completamente separado**:
   ```python
   # Proceso A (RAM física diferente)
   instancia_a._pending_approval = WeatherRequest("Madrid")
   
   # Proceso B (RAM física diferente)
   instancia_b._pending_approval = WeatherRequest("Barcelona")
   
   # No hay forma de que se "vean" entre sí sin IPC
   # (Inter-Process Communication, que NO está implementado)
   ```

2. **Decisiones independientes**:
   - Usuario A aprueba → Solo afecta instancia A
   - Usuario B rechaza → Solo afecta instancia B
   - Usuario C no responde → Solo afecta instancia C
   - Ninguna decisión cruza fronteras de proceso

3. **Ventajas de seguridad**:
   ```
   ✅ Aislamiento de seguridad (un usuario no puede aprobar para otro)
   ✅ Privacidad (un usuario no ve solicitudes de otro)
   ✅ Auditabilidad (cada decisión trazable a usuario específico)
   ✅ Sin riesgos de race conditions entre usuarios
   ```

---

## 3. Identidad Delegada: On-Behalf-Of (OBO) Flow

### Situación Actual: Service Principal Directo

```
Usuario → Bot/Agent → Azure AI Foundry
                 ↓
          (MICROSOFT_APP_ID + MICROSOFT_APP_PASSWORD)
                 ↓
          Token JWT del Service Principal
                 ↓
          Foundry ve: app_id = <service-principal-id>
                 ↓
          ❌ NO sabe quién es el usuario final
```

**Limitaciones actuales**:
- ❌ Foundry no conoce la identidad del usuario final
- ❌ Audit logs muestran siempre el Service Principal
- ❌ No puedes aplicar RBAC granular por usuario
- ❌ Compliance difícil (¿quién realmente hizo qué?)

---

### Solución: On-Behalf-Of (OBO) Flow con Identidad Delegada

#### ¿Qué es OBO Flow?

**On-Behalf-Of** permite que un Service Principal obtenga un token **en nombre de un usuario específico**, preservando la identidad del usuario final en toda la cadena de llamadas.

```
Usuario (carlos@company.com) → Autentica con Entra ID
        ↓
    Token JWT del usuario
        ↓
Bot/Agent recibe token del usuario
        ↓
Bot usa token del usuario + credenciales propias → Solicita token OBO
        ↓
    Entra ID valida:
    1. Token del usuario es válido
    2. Bot tiene permisos para actuar OBO del usuario
    3. Genera nuevo token que contiene:
       - sub: carlos@company.com (usuario original)
       - azp: <service-principal-id> (aplicación actuando)
        ↓
Bot usa token OBO → Llama Azure AI Foundry
        ↓
Foundry ve: user = carlos@company.com (actor real)
            app = <service-principal-id> (intermediario)
```

#### Implementación Paso a Paso

##### Paso 1: Configurar Service Principal con Delegación

```powershell
# Obtener objeto del Service Principal
$sp = Get-AzADServicePrincipal -ApplicationId $env:MICROSOFT_APP_ID

# Agregar permisos delegados (requiere admin consent)
# API: Azure AI Services
# Permission: user_impersonation (delegated)

az ad app permission add `
    --id $env:MICROSOFT_APP_ID `
    --api <azure-ai-services-app-id> `
    --api-permissions <user_impersonation-permission-id>=Scope

# Otorgar consent de administrador
az ad app permission admin-consent --id $env:MICROSOFT_APP_ID
```

##### Paso 2: Modificar Código para Usar OBO

**Nuevo archivo**: `app/core/identity.py`

```python
from azure.identity import OnBehalfOfCredential
from typing import Optional
import os

class UserDelegatedCredential:
    """Gestiona credenciales OBO para preservar identidad del usuario."""
    
    def __init__(self, user_token: str):
        """
        Args:
            user_token: Token JWT del usuario obtenido del canal (Teams, Bot)
        """
        self._user_token = user_token
        self._client_id = os.getenv("MICROSOFT_APP_ID")
        self._client_secret = os.getenv("MICROSOFT_APP_PASSWORD")
        self._tenant_id = os.getenv("MICROSOFT_APP_TENANTID")
    
    def get_credential(self) -> OnBehalfOfCredential:
        """Crea credencial OBO que preserva identidad del usuario."""
        return OnBehalfOfCredential(
            tenant_id=self._tenant_id,
            client_id=self._client_id,
            client_secret=self._client_secret,
            user_assertion=self._user_token,  # ← Token del usuario
        )
```

**Modificar**: `app/core/agent.py`

```python
from app.core.identity import UserDelegatedCredential

def _get_azure_credential(user_token: Optional[str] = None):
    """Devuelve credencial apropiada, con soporte para OBO.
    
    Args:
        user_token: Si se proporciona, usa OBO flow para preservar identidad.
                   Si es None, usa DefaultAzureCredential (modo desarrollo).
    """
    if user_token:
        # Modo producción: OBO flow
        delegated = UserDelegatedCredential(user_token)
        return delegated.get_credential()
    elif is_cloud_runtime():
        # Modo cloud sin token: Managed Identity
        return DefaultAzureCredential(exclude_interactive_browser_credential=True)
    else:
        # Modo desarrollo local
        return DefaultAzureCredential(
            exclude_interactive_browser_credential=True,
            exclude_shared_token_cache_credential=True,
        )

class SimpleChatAgent(AgentInterface):
    
    def __init__(self, user_token: Optional[str] = None) -> None:
        """
        Args:
            user_token: Token JWT del usuario para OBO flow.
                       Si None, usa credencial del entorno.
        """
        self._user_token = user_token
        self.chat_client: AzureAIClient | None = None
        self.agent: ChatAgent | None = None
        self.agent_thread: AgentThread | None = None
        self._pending_approval: Content | None = None
    
    def _create_chat_client(self) -> None:
        """Crea cliente con credencial apropiada (OBO o default)."""
        endpoint_api = os.getenv("ENDPOINT_API")
        deployment = os.getenv("DEPLOYMENT_NAME")
        
        # Obtener credencial con soporte OBO
        credential = _get_azure_credential(self._user_token)
        
        self.chat_client = AzureAIClient(
            project_endpoint=endpoint_api,
            model_deployment_name=deployment,
            credential=credential,  # ← Usa OBO si user_token presente
            agent_name="SimpleChatAgent",
        )
```

**Modificar**: `app/channels/m365_app.py` (canal Teams/M365)

```python
from microsoft.agents.core import TurnContext
from app.core.agent import SimpleChatAgent

async def on_message_activity(turn_context: TurnContext):
    """Maneja mensaje del usuario en Teams."""
    
    # Extraer token del usuario desde el contexto de Teams
    # Teams inyecta el token en el TurnContext automáticamente
    user_token = None
    if turn_context.activity.from_property and turn_context.activity.from_property.aad_object_id:
        # Obtener token OBO del usuario
        user_token = await turn_context.adapter.get_user_token(
            turn_context,
            connection_name="AzureAD",  # Configurado en Bot Service
            magic_code=None
        )
    
    # Crear agente con token del usuario para OBO
    agent = SimpleChatAgent(user_token=user_token.token if user_token else None)
    await agent.initialize()
    
    user_message = turn_context.activity.text
    response = await agent.process_user_message(user_message)
    
    await turn_context.send_activity(response)
    await agent.cleanup()
```

##### Paso 3: Configurar Bot Service para OAuth

```bash
# Azure Portal → Bot Service → Configuration → OAuth Connection Settings
Name: AzureAD
Service Provider: Azure Active Directory v2
Client ID: <MICROSOFT_APP_ID>
Client Secret: <MICROSOFT_APP_PASSWORD>
Tenant ID: <MICROSOFT_APP_TENANTID>
Scopes: https://cognitiveservices.azure.com/.default
```

---

### Comparación: Sin OBO vs Con OBO

#### Sin OBO (Actual)

```
Usuario: carlos@company.com
    ↓
Teams → Bot
    ↓
Bot autentica con Service Principal
    ↓
Token: {
    "oid": "<service-principal-object-id>",
    "appid": "<MICROSOFT_APP_ID>",
    "sub": "<service-principal-id>",
    "name": "Agent Bot Service"
}
    ↓
Azure AI Foundry ve:
    - actor: Agent Bot Service
    - ❌ usuario final: DESCONOCIDO
    
Audit Log:
    - timestamp: 2026-03-08 10:15:23
    - principal: Agent Bot Service
    - action: Query agent
    - ❌ No sabe que fue carlos@company.com
```

#### Con OBO (Futuro)

```
Usuario: carlos@company.com
    ↓
Teams → Bot (con token del usuario)
    ↓
Bot solicita token OBO:
    - Token usuario: carlos@company.com
    - Credenciales bot: MICROSOFT_APP_ID
    ↓
Token OBO: {
    "oid": "<carlos-object-id>",
    "upn": "carlos@company.com",
    "appid": "<MICROSOFT_APP_ID>",
    "sub": "carlos@company.com",  ← USUARIO ORIGINAL
    "azp": "<service-principal-id>",  ← BOT INTERMEDIARIO
    "name": "Carlos Muñoz"
}
    ↓
Azure AI Foundry ve:
    - actor: carlos@company.com ✅
    - intermediary: Agent Bot Service ✅
    
Audit Log:
    - timestamp: 2026-03-08 10:15:23
    - principal: carlos@company.com ✅
    - via: Agent Bot Service ✅
    - action: Query agent
    - ✅ Trazabilidad completa
```

---

### Beneficios de Identidad Delegada (OBO)

| Aspecto | Sin OBO | Con OBO |
|---------|---------|---------|
| **Identidad visible** | Service Principal | Usuario real |
| **Audit logs** | Genérico (bot) | Granular (usuario) |
| **RBAC por usuario** | ❌ No posible | ✅ Posible |
| **Compliance (GDPR, HIPAA)** | ⚠️ Difícil | ✅ Completo |
| **Data lineage** | ❌ Incompleto | ✅ Completo |
| **Right to be forgotten** | ❌ No implementable | ✅ Implementable |
| **Usage analytics** | Por bot | Por usuario real |
| **Cost allocation** | Por bot | Por usuario/departamento |
| **Row-level security** | ❌ No aplicable | ✅ Aplicable |

---

### Caso de Uso: RBAC Granular con OBO

**Escenario**: Agente empresarial con documentos sensibles

```
Documentos en Azure AI Search:
├─ Políticas HR (sensible)
│   Permissions: HR_Group
├─ Documentos financieros (muy sensible)
│   Permissions: Finance_Group
└─ Documentos públicos
    Permissions: All_Employees

Usuario A (carlos@company.com):
    - Grupos: HR_Group, All_Employees
    - Puede acceder: Políticas HR + Públicos
    - NO puede acceder: Financieros

Usuario B (ana@company.com):
    - Grupos: Finance_Group, All_Employees
    - Puede acceder: Financieros + Públicos
    - NO puede acceder: Políticas HR
```

**Sin OBO**:
```
Agente usa Service Principal
    ↓
Service Principal tiene permisos globales
    ↓
RAG devuelve TODOS los documentos
    ↓
❌ Carlos ve documentos financieros (violación)
❌ Ana ve políticas HR (violación)
```

**Con OBO**:
```
Carlos (OBO token) → Agente
    ↓
RAG query con identidad de carlos@company.com
    ↓
Azure AI Search aplica security trimming
    ↓
✅ Solo devuelve Políticas HR + Públicos

Ana (OBO token) → Agente
    ↓
RAG query con identidad de ana@company.com
    ↓
Azure AI Search aplica security trimming
    ↓
✅ Solo devuelve Financieros + Públicos
```

---

## Conclusión

### Respuestas a tus Preguntas

1. **¿Cada instancia es distinta desde el punto de vista de identidad?**  
   ✅ **SÍ, completamente**. Cada proceso Python:
   - Tiene su propia instancia de `DefaultAzureCredential`
   - Obtiene su propio token JWT (diferente `sub`, `oid`)
   - Es rastreada independientemente en audit logs
   - No comparte estado en memoria con otras instancias

2. **¿Las aprobaciones de herramientas se heredan entre instancias?**  
   ❌ **NO, nunca**. `_pending_approval` es variable de instancia:
   - Almacenada en RAM del proceso (no compartida)
   - Cada usuario aprueba/rechaza independientemente
   - Sin riesgo de aprobar herramientas de otro usuario
   - Aislamiento de seguridad completo

3. **¿Podré controlar la identidad de cada usuario con delegación?**  
   ✅ **SÍ, con On-Behalf-Of flow**:
   - Service Principal obtiene token en nombre del usuario
   - Preserva identidad del usuario final en toda la cadena
   - Permite RBAC granular por usuario
   - Audit logs muestran usuario real + bot intermediario
   - Compliance total (GDPR, HIPAA, etc.)

### Recomendación de Implementación

**Fase 1 (Actual)**: Mantén arquitectura actual para desarrollo/testing
- Cada desarrollador usa su propia identidad (Azure CLI)
- Estado completamente aislado entre instancias
- Aprobaciones independientes

**Fase 2 (Producción)**: Implementa OBO flow
- Modifica código para aceptar `user_token` (20-30 líneas)
- Configura permisos delegados en Service Principal
- Configura OAuth en Bot Service
- Despliega con soporte OBO

**Beneficios inmediatos de OBO**:
- ✅ Auditoría completa (quién hizo qué)
- ✅ RBAC por usuario (security trimming en RAG)
- ✅ Compliance automático
- ✅ Analytics granulares
- ✅ Cost allocation por usuario/departamento

