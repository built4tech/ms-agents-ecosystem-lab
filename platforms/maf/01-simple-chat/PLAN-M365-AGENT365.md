# Plan por fases: evolución de `01-simple-chat` a Microsoft 365 Copilot + Agent 365

## Contexto actual

La app actual (`main.py` + `app/core/agent.py` + `app/ui/cli.py`) funciona como chat CLI local sobre Azure AI Foundry usando MAF.

Objetivo de esta planificación: evolucionar **sin romper el flujo CLI existente**, añadiendo gradualmente:

1. Canal Microsoft 365 Copilot con Microsoft 365 Agents SDK (Python).
2. Capacidades de notificaciones de Agent 365.
3. Telemetría/observabilidad con OpenTelemetry + Agent 365 Observability.

---

## Fuentes oficiales utilizadas (Microsoft Learn)

- Microsoft 365 Agents SDK overview: https://learn.microsoft.com/microsoft-365/agents-sdk/agents-sdk-overview
- Quickstart Python (AgentApplication + aiohttp): https://learn.microsoft.com/microsoft-365/agents-sdk/quickstart?pivots=python
- Bring your agents into Microsoft 365 Copilot: https://learn.microsoft.com/microsoft-365-copilot/extensibility/bring-agents-to-copilot
- Create and deploy with Agents SDK: https://learn.microsoft.com/microsoft-365-copilot/extensibility/create-deploy-agents-sdk
- Agent 365 SDK overview: https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-sdk
- Agent 365 notifications: https://learn.microsoft.com/microsoft-agent-365/developer/notification
- Agent 365 observability: https://learn.microsoft.com/microsoft-agent-365/developer/observability
- OpenTelemetry en Application Insights: https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-overview
- Monitor AI agents in App Insights (Agent details): https://learn.microsoft.com/azure/azure-monitor/app/agents-view
- Async/proactive patterns en custom engine agents: https://learn.microsoft.com/microsoft-365-copilot/extensibility/custom-engine-agent-asynchronous-flow

> Nota importante de disponibilidad: Agent 365 SDK (notifications/observability) se encuentra en programa Frontier preview según documentación oficial.

---

## Principios de implementación incremental

- **Mantener compatibilidad**: no eliminar la CLI; agregar un segundo entrypoint para canal M365.
- **Separar núcleo y transporte**: el agente de negocio (Foundry + lógica conversacional) queda desacoplado del canal (CLI/Copilot).
- **Telemetría desde el inicio del canal**: correlación de conversación, usuario, tenant y operación.
- **Entregables pequeños**: cada fase debe terminar con criterio de salida verificable.

---

## Fase 0 — Baseline técnico y prerequisitos de tenant

### Objetivo

Preparar entorno y decisiones de arquitectura para evitar retrabajos en fases posteriores.

### Alcance de esta fase

En esta fase **no se integra aún el canal Copilot**. Se prepara la base para que las fases 1-3 sean de ensamblaje y no de descubrimiento.

### Cambios propuestos (con razón técnica)

1. **Crear un archivo de requerimientos específico para canal M365**

    - Archivo propuesto: `platforms/maf/01-simple-chat/requirements-m365.txt`
    - Contenido inicial sugerido:

    ```txt
    microsoft-agents-hosting-aiohttp
    microsoft-agents-authentication-msal
    aiohttp
    ```

    **Razón**:
    - Evitar contaminar `requirements.txt` global del laboratorio con dependencias de una sola plataforma.
    - Permitir instalación incremental por escenario (`CLI-only` vs `M365 channel`).

2. **Preparar dependencias opcionales para Agent 365 (preview) por separado**

    - Archivo propuesto: `platforms/maf/01-simple-chat/requirements-agent365-preview.txt`
    - Contenido inicial sugerido:

    ```txt
    microsoft-agents-a365-runtime
    microsoft-agents-a365-notifications
    microsoft-agents-a365-observability-core
    ```

    **Razón**:
    - Agent 365 Notifications/Observability está sujeto a Frontier preview.
    - Permite activar capacidades preview solo donde haya acceso habilitado.

3. **Ampliar el archivo de variables de entorno compartido (root)**

    - Archivo actual detectado: `/.env.example`
    - Agregar bloque para canal M365:

    ```env
    # ------------------------------------------------------------------------
    # Microsoft 365 Agents SDK / Azure Bot Service
    # ------------------------------------------------------------------------
    AGENT_HOST=localhost
    PORT=3978
    MICROSOFT_APP_ID=
    MICROSOFT_APP_PASSWORD=
    MICROSOFT_APP_TYPE=MultiTenant
    MICROSOFT_APP_TENANTID=

    # ------------------------------------------------------------------------
    # Telemetría y observabilidad
    # ------------------------------------------------------------------------
    APPLICATIONINSIGHTS_CONNECTION_STRING=
    ENABLE_OBSERVABILITY=true
    ENABLE_A365_OBSERVABILITY_EXPORTER=false
    OTEL_SERVICE_NAME=maf-simple-chat
    ```

    **Razón**:
    - El repo usa un `.env` único en raíz; mantener una única fuente reduce errores de carga de configuración.
    - Deja listos los flags de observabilidad antes de introducir código OTel.

4. **Alinear documentación local con el `.env` real del repositorio**

    - Archivo a ajustar en fase de implementación: `platforms/maf/01-simple-chat/README.md`
    - Punto a corregir: actualmente menciona `platforms/maf/01-simple-chat/.env.example`, pero el archivo existente está en raíz.

    **Razón**:
    - Evitar fallos de onboarding por rutas de archivo incorrectas.
    - Reducir tiempo de diagnóstico del equipo.

5. **Definir un “Decision Log” mínimo para identidad/autenticación**

    - Sección propuesta dentro de este mismo plan:
      - Decisión A: `AzureCliCredential` para CLI local.
      - Decisión B: `MsalConnectionManager` para canal M365.
      - Decisión C: secretos fuera de código, sólo variables de entorno.

    **Razón**:
    - Evitar mezclar credenciales interactivas de desarrollo con autenticación de canal productiva.
    - Facilitar revisiones de seguridad.

6. **Definir estándar mínimo de telemetría antes de codificar**

    - Campos mínimos por interacción:
      - `tenant_id`
      - `conversation_id`
      - `user_id` (pseudonimizado si aplica)
      - `channel` (`cli`, `m365`)
      - `operation` (`chat.turn`, `notification.email`, etc.)

    **Razón**:
    - Evitar spans/logs sin contexto de correlación.
    - Permitir troubleshooting y auditoría desde el primer release con canal M365.

### Checklist de prerequisitos (go/no-go)

#### A. Infraestructura y tenant

- [ ] Azure Subscription con permisos para crear App Service/Container Apps + Application Insights.
- [ ] Tenant M365 con capacidad de probar agentes en Copilot/Teams.
- [ ] App registration y Azure Bot Service permitidos por políticas del tenant.
- [ ] Confirmación de acceso a Frontier preview (solo si se activará Agent 365).

#### B. Entorno de desarrollo

- [ ] Python >= 3.11 validado.
- [ ] `az login` funcional.
- [ ] Entorno virtual activo.
- [ ] Instalación separada de dependencias (`requirements-m365.txt`) verificada.

#### C. Seguridad y cumplimiento

- [ ] No hay secretos en código ni en commits.
- [ ] Estrategia de rotación de `MICROSOFT_APP_PASSWORD` definida.
- [ ] Política de retención de telemetría definida (coste/compliance).

### Comandos de validación sugeridos

```bash
# desde raíz del repo
python --version
az account show

# instalación incremental para canal M365
pip install -r platforms/maf/01-simple-chat/requirements-m365.txt

# opcional preview Agent 365
pip install -r platforms/maf/01-simple-chat/requirements-agent365-preview.txt
```

### Riesgos específicos de Fase 0 y mitigación

1. **Riesgo:** dependencias preview inestables.
    - **Mitigación:** aislar en archivo de requerimientos separado y activar por feature flag.
2. **Riesgo:** inconsistencia de variables entre local y despliegue.
    - **Mitigación:** usar `.env.example` raíz como contrato único.
3. **Riesgo:** telemetría excesiva/coste inesperado.
    - **Mitigación:** definir desde inicio sampling/filtros y campos mínimos.

### Entregables de la fase

1. Archivos de dependencias segmentados (`requirements-m365.txt`, `requirements-agent365-preview.txt`).
2. `.env.example` raíz ampliado con bloque M365 + observabilidad.
3. README local alineado con rutas reales de configuración.
4. Checklist go/no-go marcado para iniciar Fase 1.

### Fase 0.5 — Decision Log de identidad y autenticación

#### Decisiones cerradas

1. **Foundry (local/dev): Entra ID-only con `AzureCliCredential`**
    - Se elimina el uso de `API_KEY` como mecanismo funcional de autenticación.
    - Requisito operativo: sesión válida con `az login`.

2. **Canal M365 (adapter/canal): autenticación de aplicación con credenciales Entra**
    - `MICROSOFT_APP_ID`, `MICROSOFT_APP_PASSWORD`, `MICROSOFT_APP_TENANTID`.
    - Flujo orientado a despliegue en App Service tras validación local/Dev Tunnel.

3. **Producción objetivo: identidad administrada (Managed Identity)**
    - Evolución prevista en fase de despliegue para minimizar secretos en runtime.

4. **Política de seguridad**
    - Sin fallback automático a API Key.
    - Secretos sólo en configuración de entorno segura; nunca en código.

#### Implicaciones técnicas

- Los fallos de autenticación pasan a ser de identidad/token/RBAC (no de clave API).
- En local, el prerrequisito de funcionamiento es `az login` con contexto correcto.
- En cloud, se requerirá asignar permisos de identidad al recurso Foundry.

#### Checklist adicional 0.5 (go/no-go)

- [ ] `API_KEY` no se usa en la ruta de autenticación de `SimpleChatAgent`.
- [ ] CLI validada con sesión `az login` activa.
- [ ] Documentación actualizada a Entra ID-only para Foundry.
- [ ] Riesgo de secretos minimizado y sin credenciales hardcodeadas.

### Criterio de salida

- Checklist de prerequisitos validado.
- Dependencias base de M365 instalables sin romper la CLI actual.
- Configuración de entorno documentada en un único contrato (`/.env.example`).
- Decision Log de autenticación aprobado y reflejado en el código base.

---

## Fase 1 — Refactor mínimo para desacoplar “core agente” de interfaces

### Objetivo

Conservar la app actual, pero preparar una capa de servicio reutilizable por CLI y por canal M365.

### Cambios de código propuestos

Estructura objetivo (mínima):

```text
app/
  core/
    agent.py                 # SimpleChatAgent actual
    chat_service.py          # NUEVO: orquesta initialize/process/cleanup
  channels/
    cli_runner.py            # NUEVO: adapta la CLI actual
    m365_runner.py           # FUTURO: entrada Agents SDK
main.py                      # se mantiene para CLI
```

### Código orientativo

```python
# app/core/chat_service.py
from app.core.agent import SimpleChatAgent

class ChatService:
    def __init__(self) -> None:
        self._agent = SimpleChatAgent()

    async def start(self) -> None:
        await self._agent.initialize()

    async def ask(self, user_text: str) -> str:
        return await self._agent.process_user_message(user_text)

    async def stop(self) -> None:
        await self._agent.cleanup()
```

### Explicación del diseño

- `ChatService` encapsula el ciclo de vida del agente.
- CLI y M365 no “conocen” detalles de Foundry/MAF.
- Reduce el riesgo de duplicar lógica al crear handler de actividades.

### Criterio de salida

- `python main.py` sigue funcionando igual.
- Tests existentes de CLI/chat siguen pasando.

---

## Fase 2 — Exponer el agente como `AgentApplication` (Microsoft 365 Agents SDK)

### Objetivo

Crear un endpoint HTTP `/api/messages` compatible con Azure Bot Service y canales M365.

### Referencia oficial

Quickstart Python usa `AgentApplication + CloudAdapter + aiohttp`.

### Cambios de código propuestos

Archivos nuevos:

- `app/channels/m365_app.py`
- `app/channels/start_server.py`
- `main_m365.py`

### Código orientativo (adaptado a tu solución)

```python
# app/channels/m365_app.py
from microsoft_agents.hosting.core import AgentApplication, TurnContext, TurnState, MemoryStorage
from microsoft_agents.hosting.aiohttp import CloudAdapter
from app.core.chat_service import ChatService

AGENT_APP = AgentApplication[TurnState](
    storage=MemoryStorage(),
    adapter=CloudAdapter(),
)

chat_service = ChatService()

@AGENT_APP.conversation_update("membersAdded")
async def on_members_added(context: TurnContext, _: TurnState):
    await context.send_activity("Hola, soy tu agente conectado a Foundry. Escribe /help para ayuda.")
    return True

@AGENT_APP.message("/help")
async def on_help(context: TurnContext, _: TurnState):
    await context.send_activity("Comandos: /help, /clear. O escribe una pregunta normal.")

@AGENT_APP.activity("message")
async def on_message(context: TurnContext, _: TurnState):
    text = (context.activity.text or "").strip()
    if text == "/clear":
        await context.send_activity("Implementa reinicio de contexto de conversación aquí.")
        return

    answer = await chat_service.ask(text)
    await context.send_activity(answer)
```

```python
# app/channels/start_server.py
from os import environ
from aiohttp.web import Request, Response, Application, run_app
from microsoft_agents.hosting.aiohttp import start_agent_process, jwt_authorization_middleware, CloudAdapter
from microsoft_agents.hosting.core import AgentApplication, AgentAuthConfiguration

def start_server(agent_application: AgentApplication, auth_configuration: AgentAuthConfiguration | None):
    async def entry_point(req: Request) -> Response:
        agent: AgentApplication = req.app["agent_app"]
        adapter: CloudAdapter = req.app["adapter"]
        return await start_agent_process(req, agent, adapter)

    app = Application(middlewares=[jwt_authorization_middleware])
    app.router.add_post("/api/messages", entry_point)
    app.router.add_get("/api/messages", lambda _: Response(status=200))
    app["agent_configuration"] = auth_configuration
    app["agent_app"] = agent_application
    app["adapter"] = agent_application.adapter
    run_app(app, host=environ.get("AGENT_HOST", "localhost"), port=int(environ.get("PORT", "3978")))
```

```python
# main_m365.py
from app.channels.m365_app import AGENT_APP
from app.channels.start_server import start_server

if __name__ == "__main__":
    start_server(AGENT_APP, None)
```

### Explicación del código

- `AgentApplication` centraliza routing de actividades (`message`, `conversationUpdate`, comandos).
- `CloudAdapter` realiza bridge protocolo actividad ↔ endpoint HTTP.
- `start_agent_process` procesa peticiones entrantes del canal (Copilot/Teams vía Bot Service).
- Reutilizas tu lógica Foundry llamando `chat_service.ask()` dentro de `@AGENT_APP.activity("message")`.

### Criterio de salida

- `python main_m365.py` levanta servidor en `http://localhost:3978/api/messages`.
- Prueba local con Agents Playground responde correctamente.

---

## Fase 3 — Integración y publicación en Microsoft 365 Copilot

### Objetivo

Conectar el endpoint de Fase 2 con Azure Bot Service + manifiesto y habilitar uso dentro de Copilot.

### Cambios/acciones

1. Crear/usar app registration + Azure Bot Service.
2. Configurar secretos/credenciales en entorno.
3. Generar o adaptar manifest M365 Copilot y empaquetar `.zip`.
4. Desplegar endpoint público (App Service/Container Apps u otro hosting).

### Código orientativo de configuración

```python
from os import environ
from microsoft_agents.activity import load_configuration_from_env
from microsoft_agents.authentication.msal import MsalConnectionManager
from microsoft_agents.hosting.aiohttp import CloudAdapter

agents_sdk_config = load_configuration_from_env(environ)
connection_manager = MsalConnectionManager(**agents_sdk_config)
adapter = CloudAdapter(connection_manager=connection_manager)
```

### Explicación del código

- `load_configuration_from_env` unifica configuración de autenticación.
- `MsalConnectionManager` maneja el flujo de tokens para canal seguro.
- Esta configuración es base para añadir auth handlers (por ejemplo `AGENTIC`) en notificaciones/observabilidad.

### Criterio de salida

- Agente aparece en Copilot y responde mensajes básicos end-to-end.

---

## Fase 4 — Notificaciones de Agent 365 (email, Word/Excel/PowerPoint, lifecycle)

### Objetivo

Permitir que el agente reciba y procese eventos asíncronos de M365 además del chat interactivo.

### Dependencias (según docs)

```bash
pip install microsoft-agents-a365-notifications
pip install microsoft-agents-a365-runtime
```

### Cambios de código propuestos

Añadir en `app/channels/m365_app.py`:

```python
from microsoft_agents_a365.notifications import AgentNotification
from microsoft_agents.activity import ChannelId

agent_notification = AgentNotification(AGENT_APP)

@agent_notification.on_email()
async def handle_email(context, state, notification):
    email = notification.email_notification
    if not email:
        await context.send_activity("No se encontró payload de email")
        return

    # Ejemplo: enrutar asunto/cuerpo al core conversacional
    summary = await chat_service.ask("Resume este email: " + (email.html_body or ""))
    await context.send_activity(summary)

@agent_notification.on_word()
async def handle_word_comment(context, state, notification):
    comment = notification.wpx_comment_notification
    await context.send_activity(f"Comentario recibido. documentId={comment.document_id}")

@agent_notification.on_agent_lifecycle_notification("*")
async def handle_lifecycle(context, state, notification):
    event = notification.agent_lifecycle_notification.lifecycle_event_type
    await context.send_activity(f"Lifecycle event: {event}")
```

### Explicación del código

- `AgentNotification` añade rutas especializadas sobre `AgentApplication`.
- Los decoradores (`on_email`, `on_word`, etc.) simplifican el filtrado por tipo.
- Permite implementar procesamiento asíncrono sin bloquear el flujo de chat.

### Criterio de salida

- Se procesa al menos un tipo de notificación (`email`) en entorno de pruebas.
- Logging funcional de eventos lifecycle.

---

## Fase 5 — Observabilidad de Agent 365 + OpenTelemetry + Application Insights

### Objetivo

Tener trazabilidad de interacciones, llamadas al modelo, errores y uso por conversación/tenant/agent.

### Dependencias (según docs)

```bash
pip install microsoft-agents-a365-observability-core
pip install microsoft-agents-a365-runtime
pip install azure-monitor-opentelemetry
```

### Cambios de código propuestos

Archivo nuevo `app/observability/setup.py`:

```python
import os
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import trace
from microsoft_agents_a365.observability.core import config as a365_config

_cached_token: str | None = None

def set_observability_token(token: str) -> None:
    global _cached_token
    _cached_token = token

def token_resolver(agent_id: str, tenant_id: str) -> str | None:
    return _cached_token

def configure_observability() -> None:
    conn = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if conn:
        configure_azure_monitor(connection_string=conn)

    a365_config.configure(
        service_name="maf-simple-chat",
        service_namespace="platforms.maf",
        token_resolver=token_resolver,
    )

def get_tracer():
    return trace.get_tracer(__name__)
```

En el handler de mensajes:

```python
tracer = get_tracer()
with tracer.start_as_current_span("chat.turn") as span:
    span.set_attribute("agent.channel", "m365")
    span.set_attribute("agent.user_id", context.activity.from_property.id if context.activity.from_property else "unknown")
    answer = await chat_service.ask(text)
```

### Explicación del código

- `configure_azure_monitor` exporta trazas/métricas/logs a Application Insights.
- `a365_config.configure(...)` activa observabilidad Agent 365 con `token_resolver`.
- Span `chat.turn` agrega contexto de negocio para troubleshooting.
- La clave es correlacionar `conversation_id`, `tenant_id`, `agent_id`, tipo de actividad y errores.

### Criterio de salida

- Se observan spans en Application Insights (tabla de traces/dependencies).
- Agent details muestra actividad del agente cuando aplica.

---

## Fase 6 — Mensajería asíncrona/proactiva y endurecimiento operativo

### Objetivo

Implementar experiencias no bloqueantes (long-running + follow-up) y prácticas de producción.

### Cambios/acciones

1. Almacenar `conversation_id` por usuario para mensajes proactivos.
2. Añadir job asíncrono (cola o task worker) para operaciones largas.
3. Enviar respuesta inicial rápida + notificación de finalización.
4. Definir política de retries, idempotencia y manejo de fallos de canal.

### Código orientativo

```python
conversation_storage: dict[str, str] = {}

@AGENT_APP.activity("message")
async def on_message(context, _):
    user_id = context.activity.from_property.id
    conv_id = context.activity.conversation.id
    conversation_storage[user_id] = conv_id
    await context.send_activity("Tu solicitud está en proceso. Te aviso cuando termine.")
    # lanzar tarea asíncrona y luego enviar follow-up
```

### Explicación del código

- Guardar conversación por usuario habilita envío proactivo posterior.
- Evita bloquear turnos de chat mientras corre una operación larga.
- Debes instrumentar estado (`queued`, `running`, `completed`, `failed`) para observabilidad.

### Criterio de salida

- Flujo de tarea larga con follow-up verificado en canal M365.
- Métricas de latencia y tasa de error disponibles en App Insights.

---

## Plan de ejecución recomendado (iteraciones)

- **Iteración 1**: Fases 0-2 (sin notificaciones/observabilidad avanzada).
- **Iteración 2**: Fase 3 (Copilot end-to-end) + hardening básico de auth.
- **Iteración 3**: Fases 4-5 (notifications + observabilidad).
- **Iteración 4**: Fase 6 (proactivo + operación en producción).

---

## Riesgos y mitigaciones

1. **Disponibilidad preview (Agent 365)**
   - Mitigación: mantener arquitectura dual; Copilot base con Agents SDK primero.
2. **Acoplamiento de canal y core conversacional**
   - Mitigación: `ChatService` como borde único de negocio.
3. **Coste/ruido de telemetría**
   - Mitigación: sampling y filtros OTel desde el inicio.
4. **Gestión de tokens en observabilidad**
   - Mitigación: cache segura + rotación + fallback controlado.

---

## Definición de “listo” global

La migración se considera completada cuando:

1. El agente responde en CLI y en Copilot con el mismo núcleo de negocio.
2. Procesa al menos notificaciones `email` y un evento `lifecycle`.
3. Tiene trazas end-to-end en Application Insights con correlación por conversación y usuario.
4. Soporta al menos un caso de operación asíncrona con mensaje de seguimiento.
