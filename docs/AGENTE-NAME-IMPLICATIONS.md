# Implicaciones del Parámetro `name` en ChatAgent

**Fecha**: 2026-03-08  
**Contexto**: Endpoint `agent-identity-viewer.services.ai.azure.com`

---

## Situación Actual

### Código Actual
```python
self.agent = ChatAgent(
    chat_client=self.chat_client,
    name="SimpleChatAgent",  # ← AGREGADO RECIENTEMENTE
    instructions=self.AGENT_PROMPT,
    tools=[get_weather_by_city, web_search_tool],
)
```

### Error Observado (logs HTTP)
```
POST https://agent-identity-viewer.services.ai.azure.com/agents/SimpleChatAgent/versions
Response: 404 Resource not found
```

**Pero el agente funciona correctamente** ✅

---

## ¿Por Qué Funciona Si Da 404?

El framework `agent-framework-azure-ai` tiene dos modos:

### Modo 1: Agente Referenciado (Visual)
Intenta cargar el agente desde Foundry:
```
1. Cliente envía: agent_name="SimpleChatAgent"
2. Foundry busca agente con ese nombre en el proyecto
3. Si lo encuentra → carga configuración (instructions, tools, RAG, MCPs)
4. Si NO lo encuentra → Error 404
```

### Modo 2: Agente Programático (Fallback)
Si el agente no existe en Foundry y proporcionas `instructions` + `tools` en código:
```
1. Framework detecta: "Agente no encontrado en Foundry"
2. Framework usa instrucciones y tools del código
3. El agente funciona en "modo local" (sin persistencia)
4. El `name` se usa solo para identificación en logs/tracing
```

**En tu caso**: Estás en Modo 2 (Programático). El 404 es esperado porque "SimpleChatAgent" no existe en Foundry UI.

---

## Comparación Visual

### Tu Situación Actual

```
┌──────────────────────────────────────┐
│ Azure AI Foundry Portal              │
│                                       │
│  Project: agent-identity-viewer      │
│  Agents: (vacío o solo ejemplos)     │
│                                       │
│  ❌ "SimpleChatAgent" NO existe aquí │
└──────────────────────────────────────┘
             ↑ (intenta buscar, 404)
             │
┌──────────────────────────────────────┐
│ Tu Código Python                     │
│                                       │
│  ChatAgent(                          │
│    name="SimpleChatAgent",  ← 404    │
│    instructions="...",      ← Usado  │
│    tools=[...]             ← Usado   │
│  )                                    │
│                                       │
│  ✅ Funciona en modo local           │
│  ⚠️  Nada aparece en Foundry UI      │
│  ⚠️  No persiste entre ejecuciones   │
└──────────────────────────────────────┘
```

### Modo Visual (Futuro)

```
┌──────────────────────────────────────┐
│ Azure AI Foundry Portal (UI)         │
│                                       │
│  [Create Agent] →                    │
│    Name: SimpleChatAgent             │
│    Instructions: "Eres un agente..." │
│    Model: gpt-4o                     │
│    Tools: web_search, custom_tool    │
│    RAG: company-docs                 │
│    Security: Content Safety ON       │
│  [Save] → Version 1.0.0 created ✅   │
│                                       │
│  ✅ Visible en UI                    │
│  ✅ Editable sin código              │
│  ✅ Versionado automático            │
└──────────────────────────────────────┘
             ↓ (carga configuración)
             │ (200 OK)
┌──────────────────────────────────────┐
│ Tu Código Python (SIMPLIFICADO)     │
│                                       │
│  AzureAIClient(                      │
│    agent_name="SimpleChatAgent"      │
│  )                                    │
│  ChatAgent(chat_client=client)       │
│                                       │
│  ✅ Carga todo desde Foundry         │
│  ✅ Sin instructions en código       │
│  ✅ Sin tools en código              │
│  ✅ RAG automático                   │
│  ✅ Versionado                       │
└──────────────────────────────────────┘
```

---

## Implicaciones de Múltiples Usuarios

### Escenario 1: Modo Actual (Programático)

**3 usuarios ejecutan simultáneamente**:

```
Usuario A (laptop)     Usuario B (servidor)   Usuario C (local)
        ↓                      ↓                      ↓
 Proceso Python A       Proceso Python B       Proceso Python C
        ↓                      ↓                      ↓
 ChatAgent(...)         ChatAgent(...)         ChatAgent(...)
 name="SimpleChatAgent" name="SimpleChatAgent" name="SimpleChatAgent"
        ↓                      ↓                      ↓
 Instancia en RAM A     Instancia en RAM B     Instancia en RAM C
        ↓                      ↓                      ↓
 Conversación A         Conversación B         Conversación C
 (independiente)        (independiente)        (independiente)
```

**Características**:
- ✅ Sin colisiones (cada proceso es independiente)
- ✅ Sin compartir estado entre usuarios
- ⚠️ Mismo nombre en tracing (difícil distinguir en logs)
- ⚠️ Si uno actualiza código, otros no se enteran

**Logs en Application Insights**:
```
2026-03-08 10:15:23 | SimpleChatAgent | user_message: "Hola" | duration: 1.2s
2026-03-08 10:15:24 | SimpleChatAgent | user_message: "Adiós" | duration: 0.8s
2026-03-08 10:15:25 | SimpleChatAgent | user_message: "Hola" | duration: 1.1s

¿Quién dijo qué? ⚠️ Difícil de trazar sin contexto adicional
```

### Escenario 2: Modo Futuro (Visual)

**3 usuarios con agente en Foundry**:

```
Usuario A (laptop)     Usuario B (servidor)   Usuario C (local)
        ↓                      ↓                      ↓
 Carga agente desde     Carga agente desde     Carga agente desde
 Foundry v1.0.0         Foundry v1.0.0         Foundry v1.0.0
        ↓                      ↓                      ↓
 Thread A (UUID: abc)   Thread B (UUID: def)   Thread C (UUID: ghi)
        ↓                      ↓                      ↓
 Conversación A         Conversación B         Conversación C
 (mismo agente,         (mismo agente,         (mismo agente,
  thread diferente)      thread diferente)      thread diferente)
```

**Características**:
- ✅ Todos usan la misma configuración (centralizada)
- ✅ Threads independientes (sin compartir conversación)
- ✅ Trazabilidad granular (thread_id único)
- ✅ Si actualizas agente a v1.1.0, elige versión en código
- ✅ A/B testing posible (50% v1.0.0, 50% v1.1.0)

**Logs en Application Insights**:
```
2026-03-08 10:15:23 | SimpleChatAgent v1.0.0 | thread_id: abc123 | user: carlos@company.com | message: "Hola"
2026-03-08 10:15:24 | SimpleChatAgent v1.0.0 | thread_id: def456 | user: ana@company.com | message: "Adiós"
2026-03-08 10:15:25 | SimpleChatAgent v1.0.0 | thread_id: ghi789 | user: juan@company.com | message: "Info"

✅ Trazabilidad completa
```

---

## Ciclo de Vida del Agente

### Modo Actual (Programático)

```
┌─────────────────────────┐
│ Usuario ejecuta script  │
│ python main.py          │
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│ SimpleChatAgent()       │
│ .__init__()             │
│ .initialize()           │
│   ├─ Crea client        │
│   ├─ Crea agente local  │
│   └─ Crea thread        │
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│ Loop conversacional     │
│ while True:             │
│   input() → run()       │
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│ Usuario: exit           │
│ .cleanup()              │
└───────────┬─────────────┘
            ↓
┌─────────────────────────┐
│ Proceso termina         │
│ ❌ Agente destruido     │
│ ❌ Thread perdido       │
│ ❌ Historial perdido    │
└─────────────────────────┘

Si ejecutas de nuevo:
→ Todo se recrea desde cero
→ Sin memoria del estado anterior
```

### Modo Futuro (Visual con Foundry)

```
┌──────────────────────────────────────┐
│ Agente existe en Foundry (persistente)
│ Name: SimpleChatAgent                │
│ Version: 1.0.0                       │
│ Status: Active                       │
├──────────────────────────────────────┤
│ Instructions: "Eres un agente..."    │
│ Tools: [web_search, weather]         │
│ RAG: company-docs                    │
│ Security: Content Safety ON          │
└───────────────┬──────────────────────┘
                ↓ (persiste siempre)
┌───────────────────────────────────────┐
│ Usuario A ejecuta script              │
│ python main.py                        │
├───────────────────────────────────────┤
│ Carga agente desde Foundry ✅         │
│ Crea thread nuevo (UUID: abc)         │
│ Conversación... → exit                │
│ Thread cerrado                        │
└───────────────┬───────────────────────┘
                ↓
┌───────────────────────────────────────┐
│ Usuario B ejecuta script              │
│ python main.py                        │
├───────────────────────────────────────┤
│ Carga MISMO agent desde Foundry ✅    │
│ Crea thread nuevo (UUID: def)         │
│ Conversación... → exit                │
│ Thread cerrado                        │
└───────────────┬───────────────────────┘
                ↓
┌───────────────────────────────────────┐
│ Agente sigue existiendo en Foundry   │
│ ✅ Configuración persiste             │
│ ✅ Versionado intacto                 │
│ ✅ Métricas acumuladas                │
└───────────────────────────────────────┘

Si actualizas agente en UI a v1.1.0:
→ Próximas ejecuciones usan v1.1.0
→ Sin cambios en código
```

---

## ¿Qué Sucede con el Parámetro `name` en Cada Escenario?

### Cuando `name` NO existe en Foundry (tu caso actual)

```python
ChatAgent(
    chat_client=chat_client,
    name="SimpleChatAgent",  # ← No existe en Foundry
    instructions="Eres un agente...",
    tools=[web_search_tool]
)
```

**Flow**:
1. Framework intenta: `GET /agents/SimpleChatAgent` → **404**
2. Framework detecta: "Instructions y tools presentes en código"
3. Framework crea agente **local en memoria** usando código
4. `name` se usa para:
   - Logging (`logger.info(f"Agent {name} initialized")`)
   - Tracing (OpenTelemetry span attribute `agent.name`)
   - Identificación en Application Insights

**Resultado**:
- ✅ Agente funciona
- ⚠️ En modo local (no visual)
- ⚠️ No aparece en Foundry UI
- ⚠️ No persiste

### Cuando `name` SÍ existe en Foundry (futuro)

```python
# Primero: Crear "SimpleChatAgent" en Foundry UI
# Luego:
AzureAIClient(
    project_endpoint=endpoint,
    agent_name="SimpleChatAgent",  # ← Existe en Foundry
    use_latest_version=True
)
ChatAgent(chat_client=client)
# ← Sin instructions ni tools (vienen de Foundry)
```

**Flow**:
1. Cliente envía: `GET /agents/SimpleChatAgent/versions/latest` → **200 OK**
2. Foundry devuelve configuración completa:
   ```json
   {
     "name": "SimpleChatAgent",
     "version": "1.0.0",
     "instructions": "Eres un agente...",
     "tools": ["web_search", "custom_tool"],
     "rag_sources": ["company-docs"],
     "security": {"content_safety": true}
   }
   ```
3. Framework carga agente con configuración de Foundry
4. Ignora `instructions` y `tools` del código (si los pusiste)

**Resultado**:
- ✅ Agente cargado desde Foundry
- ✅ Aparece en UI (porque lo creaste allí)
- ✅ Persiste entre ejecuciones
- ✅ Versionado automático
- ✅ Editable sin código

---

## Recomendaciones

### Ahora (Modo Programático)

1. **Mantén el `name` agregado**:
   - Mejora trazabilidad en logs
   - Necesario para endpoint `.services.ai.azure.com`
   - Sin efectos negativos

2. **Acepta el 404**:
   - Es esperado (agente no en Foundry)
   - No afecta funcionalidad
   - Desaparecerá cuando migres a visual

3. **Considera agregar tracing adicional**:
   ```python
   self.agent = ChatAgent(
       chat_client=self.chat_client,
       name=f"SimpleChatAgent-{os.getenv('USER', 'unknown')}",
       # ↑ Distingue instancias en logs multiuser
       instructions=self.AGENT_PROMPT,
       tools=[get_weather_by_city, web_search_tool],
   )
   ```

### Más Adelante (Migración a Visual)

1. **Crear agente en Foundry UI** primero
2. **Actualizar código**:
   ```python
   # Mover agent_name a AzureAIClient
   self.chat_client = AzureAIClient(
       project_endpoint=endpoint_api,
       model_deployment_name=deployment,
       credential=credential,
       agent_name="SimpleChatAgent",
       use_latest_version=True
   )
   
   # Simplificar ChatAgent
   self.agent = ChatAgent(chat_client=self.chat_client)
   ```
3. **Eliminar `AGENT_PROMPT` y `tools` del código**
4. **Configurar todo desde Foundry UI**

---

## Conclusión

| Pregunta | Respuesta |
|----------|-----------|
| **¿Aparece en Foundry UI?** | ❌ No (en modo actual). Solo si lo creas manualmente en la UI. |
| **¿Se destruye al salir?** | ✅ Sí (en modo actual). El agente es local/temporal. |
| **¿Múltiples usuarios?** | ✅ Sin problemas. Cada uno tiene su instancia independiente. |
| **¿Por qué el 404?** | Intenta cargar desde Foundry, no lo encuentra, usa fallback local. |
| **¿Funciona igual?** | ✅ Sí, funciona correctamente en modo programático. |
| **¿Cuándo migrar a visual?** | Cuando quieras RAG, MCPs, o editar sin deploy. |

