# Guía de flujo runtime M365

Este documento explica en detalle cómo funciona la integración runtime M365, desde `main_m365.py` hasta el procesamiento de actividades y la conexión con tu agente de chat existente.

## Lectura lineal recomendada

1. Plan general y decisiones por fases: [01-PLAN-M365-AGENT365.md](01-PLAN-M365-AGENT365.md)
2. Esta guía runtime (implementación y pruebas locales de endpoint)
3. Ejecución operativa Go/No-Go: [03-RUNBOOK-PREFASE3-M365.md](03-RUNBOOK-PREFASE3-M365.md)

Esta secuencia te permite pasar de visión estratégica (plan) a detalle operativo (flujo runtime).

---

## 1) Qué problema resuelve esta integración runtime

Antes de esta integración, tu agente solo se ejecutaba en CLI (hoy disponible como `main.py cli` o `main_cli.py`).

Con esta integración, añadimos un **endpoint HTTP** compatible con el protocolo de actividades de Microsoft 365 Agents SDK para poder recibir eventos desde canales (Copilot/Teams/Playground/Bot pipeline).

Resultado: ahora existen dos modos de entrada:

- `main.py` -> dispatcher (`sin argumentos` arranca `main_m365.py`, `cli` arranca `main_cli.py`)
- `main_m365.py` -> endpoint HTTP `/api/messages`

Ambas usan el mismo núcleo de negocio (`ChatService` -> `SimpleChatAgent`).

---

## 2) Mapa de archivos y responsabilidad

### 2.1 `main_m365.py`

Responsabilidad: arrancar el servidor web para el canal M365.

```python
from app.channels.m365_app import AGENT_APP
from app.channels.start_server import start_server

if __name__ == "__main__":
    start_server(AGENT_APP, None)
```

- Importa la app de actividades (`AGENT_APP`) con sus handlers.
- Llama al bootstrap de servidor (`start_server`).
- `None` en `auth_configuration` indica que en esta fase no se inyecta configuración de auth avanzada adicional por ese parámetro.

---

### 2.2 `app/channels/start_server.py`

Responsabilidad: levantar `aiohttp` y exponer rutas HTTP.

Elementos clave:

1. `Application(middlewares=[jwt_authorization_middleware])`
   - Inserta middleware de autorización JWT del SDK.
   - En escenarios reales de canal, aquí se valida contexto de seguridad de la actividad.

2. `app.router.add_post("/api/messages", entry_point)`
   - Ruta principal del protocolo de actividades.

3. `entry_point(req)`
   - Obtiene de `app`:
     - `agent_app` (`AgentApplication`)
     - `adapter` (`CloudAdapter`)
   - Ejecuta:
     - `start_agent_process(req, agent, adapter)`
   - Este método parsea el request, valida Activity y dispara el pipeline del SDK.

4. `app.router.add_get("/api/messages", lambda _: Response(status=200))`
   - Health-check simple.
   - No procesa lógica de chat, solo confirma disponibilidad HTTP.

5. `run_app(..., host=AGENT_HOST, port=PORT)`
   - Usa variables de entorno (`.env`) para binding de red.

---

### 2.3 `app/channels/m365_app.py`

Responsabilidad: definir cómo responde el agente a actividades entrantes.

#### 2.3.1 Construcción de la app

```python
AGENT_APP = AgentApplication[TurnState](
    storage=MemoryStorage(),
    adapter=CloudAdapter(),
)
```

- `AgentApplication`: router de actividades (`message`, `conversationUpdate`, etc.).
- `MemoryStorage`: almacenamiento en memoria (válido para desarrollo/local).
- `CloudAdapter`: traduce HTTP <-> Activity protocol.

#### 2.3.2 `ChatService` compartido

```python
chat_service = ChatService()
_is_started = False
_startup_lock = asyncio.Lock()
```

- Se crea una única instancia de servicio de negocio para este proceso.
- `_is_started` evita inicializaciones repetidas.
- `_startup_lock` evita condición de carrera en concurrencia.

#### 2.3.3 Método `_ensure_started()`

Objetivo: inicializar de forma perezosa y segura.

Flujo:

1. Si `_is_started` es `True`, retorna inmediatamente.
2. Si no, entra al lock async.
3. Revalida `_is_started` (doble check).
4. Llama `await chat_service.start()` -> internamente `SimpleChatAgent.initialize()`.
5. Marca `_is_started = True`.

Esto evita que dos requests paralelas inicialicen Foundry dos veces.

#### 2.3.4 Handler `on_members_added`

Decorador:

```python
@AGENT_APP.conversation_update("membersAdded")
```

Se activa cuando un usuario se agrega a la conversación.

Comportamiento:

- Envía mensaje de bienvenida.
- `return True` para indicar que el evento fue atendido.

#### 2.3.5 Handler `on_help`

Decorador:

```python
@AGENT_APP.message("/help")
```

Ruta especializada para comando `/help`.

Comportamiento:

- Devuelve texto de ayuda.
- No invoca Foundry.

#### 2.3.6 Handler principal `on_message`

Decorador:

```python
@AGENT_APP.activity("message")
```

Este es el handler general para actividades de tipo mensaje.

Flujo interno exacto:

1. `await _ensure_started()`
   - Garantiza inicialización del agente antes de procesar texto.

2. `text = (context.activity.text or "").strip()`
   - Extrae texto robustamente y limpia espacios.

3. Si `text` vacío:
   - Responde "No recibí texto en el mensaje.".

4. Si `text` es `exit/salir/quit`:
   - Responde que en canal M365 no cierra sesión por comando de salida.

5. Si `text == "/clear"`:
   - Llama `chat_service.ask("clear")` para reutilizar semántica ya existente de CLI.

6. Caso normal:
   - `answer = await chat_service.ask(text)`
   - `await context.send_activity(answer)`

Este último punto conecta el canal M365 runtime con tu agente original: sigue usando la misma lógica de negocio y modelo Foundry.

---

### 2.4 `app/core/agent_viewer.py`

Responsabilidad: desacoplar canal de negocio.

- `start()` -> inicializa `SimpleChatAgent`
- `ask(text)` -> delega procesamiento a `process_user_message`
- `stop()` -> cleanup

Así, tanto CLI como M365 canal consumen una API común.

---

## 3) Flujo end-to-end de una llamada POST

## 3.1 Camino exitoso esperado

1. Cliente hace `POST /api/messages` con Activity válida.
2. `start_server.entry_point` llama `start_agent_process`.
3. `CloudAdapter` valida y transforma request en `Activity`.
4. `AgentApplication` enruta según tipo/trigger:
   - `/help` -> `on_help`
   - `membersAdded` -> `on_members_added`
   - `message` -> `on_message`
5. `on_message` llama `ChatService`.
6. `ChatService` llama `SimpleChatAgent.process_user_message`.
7. Se obtiene respuesta de Foundry (o lógica local para comandos).
8. `context.send_activity(...)` devuelve respuesta al canal.

---

## 4) Endpoints disponibles y objetivo

## 4.1 `GET /api/messages`

Objetivo: health-check.

- Tipo: verificación técnica de disponibilidad.
- Respuesta esperada: `200`.
- No usa Foundry ni procesa texto de usuario.

## 4.2 `POST /api/messages`

Objetivo: procesar actividades de canal.

- Tipo: endpoint de negocio/protocolo.
- Espera payload con estructura `Activity` (no JSON libre).

---

## 5) Por qué `{"text":"..."}` falla

El SDK valida Activity con Pydantic.

Campo mínimo crítico que faltaba en tu prueba: `type`.

Error típico observado:

- `ValidationError: type - Field required`

Por eso un body plano con solo `text` produce `500`.

---

## 6) Estructura esperada del payload POST

Ejemplo mínimo útil para prueba manual:

```json
{
  "type": "message",
  "id": "activity-2",
  "timestamp": "2026-02-22T14:50:00.000Z",
  "serviceUrl": "http://localhost:3978",
  "channelId": "emulator",
  "from": { "id": "user-1", "name": "Carlos" },
  "conversation": { "id": "conv-2", "conversationType": "personal" },
  "recipient": { "id": "bot-1", "name": "SimpleChat" },
  "text": "Quien fue Cristobal Colon",
  "deliveryMode": "expectReplies"
}
```

Notas importantes:

- `type="message"` es obligatorio para enrutar al handler de mensaje.
- `deliveryMode="expectReplies"` permite recibir respuesta en el mismo HTTP response cuando haces pruebas manuales.
- Sin `expectReplies`, el adapter intenta responder por callback (`/v3/conversations/...`), que no existe en tu prueba manual y genera error 404/500.

### 6.1 Estructura completa de una Activity (campos y objetivo)

> Referencia conceptual: Bot Framework Activity schema + Microsoft 365 Agents SDK.

#### Campos de primer nivel

| Campo | Objetivo | ¿Obligatorio en tu caso? |
| --- | --- | --- |
| `type` | Define el tipo de actividad (`message`, `conversationUpdate`, etc.). Determina el handler. | Sí |
| `id` | Identificador único de la actividad entrante. Útil para correlación y reply. | Recomendado |
| `timestamp` | Momento de emisión. Útil para trazabilidad/orden temporal. | Recomendado |
| `serviceUrl` | URL base del servicio de canal para callbacks de respuesta. | Sí para callbacks |
| `channelId` | Canal origen (`msteams`, `emulator`, etc.). | Sí |
| `from` | Actor emisor de la actividad (usuario/sistema). | Sí |
| `recipient` | Receptor esperado (bot/agente). | Sí |
| `conversation` | Contexto conversacional (id y tipo). | Sí |
| `text` | Texto del usuario (en actividades `message`). | Sí para mensajes de texto |
| `deliveryMode` | Modo de entrega de la respuesta (`expectReplies` para respuesta HTTP directa). | No, pero clave en pruebas manuales |
| `locale` | Idioma/cultura del mensaje (`es-ES`, `en-US`, etc.). | Opcional |
| `textFormat` | Formato del texto (`plain`, `markdown`, etc.). | Opcional |
| `entities` | Metadatos estructurados (mentions, clientInfo, productInfo). | Opcional |
| `attachments` | Archivos/cards adjuntos. | Opcional |
| `channelData` | Datos específicos del canal (tenant, contexto de producto). | Opcional |
| `name` | Nombre de evento en actividades de evento/notificación. | Opcional (según tipo) |
| `replyToId` | Actividad a la que responde esta Activity. | Opcional |
| `value` | Payload estructurado para acciones/comandos. | Opcional |
| `membersAdded` / `membersRemoved` | Usuarios añadidos/eliminados en `conversationUpdate`. | Según tipo |

#### Objetivo de objetos anidados más usados

| Objeto | Campos comunes | Objetivo |
| --- | --- | --- |
| `from` | `id`, `name`, `role` | Identifica al emisor para lógica de autorización/personalización. |
| `recipient` | `id`, `name` | Identifica el agente destino de la actividad. |
| `conversation` | `id`, `conversationType`, `tenantId` | Agrupa turnos de una misma conversación/sesión. |
| `channelData` | `tenant`, `productContext`, etc. | Extiende contexto con datos propios del canal. |

#### Qué mínimo usar en tus pruebas locales

Para `POST` manual funcional en tu endpoint, usa al menos:

- `type`
- `id`
- `serviceUrl`
- `channelId`
- `from`
- `recipient`
- `conversation`
- `text`
- `deliveryMode="expectReplies"` (si quieres respuesta en el mismo HTTP response)

---

## 7) Tipos de invocación válidos por endpoint

## 7.1 GET `/api/messages`

- Método: `GET`
- Body: ninguno
- Uso: health-check
- Respuesta: `200`

## 7.2 POST `/api/messages`

- Método: `POST`
- Content-Type: `application/json`
- Body: Activity protocol
- Casos funcionales en tu implementación actual:

1. `type=message` + `text=/help` -> responde texto de ayuda
2. `type=message` + `text=/clear` -> limpia contexto conversacional (vía `ChatService`)
3. `type=message` + texto normal -> consulta Foundry y responde
4. `type=conversationUpdate` + evento `membersAdded` -> mensaje de bienvenida

---

## 8) Diferencia entre prueba manual y canal real (Copilot/Teams)

## 8.1 Prueba manual (PowerShell)

- Tú construyes el Activity.
- Recomendado `deliveryMode=expectReplies`.
- Recibes respuesta inmediata en JSON.

## 8.2 Canal real

- El canal construye y firma actividades.
- El adapter gestiona callbacks y seguridad del protocolo.
- No necesitas fabricar payloads manualmente.

---

## 9) Diagnóstico de errores frecuentes

1. **500 con ValidationError `type required`**
   - Causa: body no es Activity válida.
   - Solución: incluir `type` y estructura base.

2. **404 en `/v3/conversations/...` + 500 final**
   - Causa: prueba manual sin `expectReplies`.
   - Solución: agregar `deliveryMode: expectReplies`.

3. **Error de bind puerto 3978 (Errno 10048)**
   - Causa: servidor ya ejecutándose.
   - Solución: cerrar proceso previo o cambiar `PORT`.

4. **Errores de token Entra ID**
   - Causa: sesión `az login` inválida/expirada o contexto incorrecto.
   - Solución: reautenticar y validar `az account show`.

---

## 10) Comandos de prueba recomendados (PowerShell)

### 10.1 Levantar servidor

```powershell
cd .
python .\main_m365.py
```

### 10.2 Health-check

```powershell
Invoke-RestMethod -Uri "http://localhost:3978/api/messages" -Method Get
```

### 10.3 POST funcional con expectReplies

```powershell
$body = @{
  type = 'message'
  id = 'activity-local-1'
  timestamp = (Get-Date).ToString('o')
  serviceUrl = 'http://localhost:3978'
  channelId = 'emulator'
  from = @{ id='user-1'; name='Carlos' }
  conversation = @{ id='conv-local-1'; conversationType='personal' }
  recipient = @{ id='bot-1'; name='SimpleChat' }
  text = 'Hola'
  deliveryMode = 'expectReplies'
} | ConvertTo-Json -Depth 8

Invoke-RestMethod -Uri "http://localhost:3978/api/messages" -Method Post -ContentType "application/json" -Body $body | ConvertTo-Json -Depth 10
```

---

## 11) Resumen corto (para recordar)

- `main_m365.py` solo arranca servidor + app de actividades.
- `start_server.py` expone `/api/messages` y delega al adapter.
- `m365_app.py` define rutas de actividad y conecta con `ChatService`.
- `ChatService` conecta con tu `SimpleChatAgent` (Foundry).
- POST manual requiere Activity válida.
- Para pruebas manuales sin callback externo, usa `deliveryMode=expectReplies`.

---

## 12) Checklist de preproducción antes de Fase 3

Usa este checklist como criterio Go/No-Go antes de pasar a despliegue/publicación.

Si quieres ejecutar este checklist en modo operativo paso a paso, usa: [03-RUNBOOK-PREFASE3-M365.md](03-RUNBOOK-PREFASE3-M365.md)

### A. Funcionalidad base

- [ ] `main.py cli` (CLI) sigue funcionando sin regresiones.
- [ ] `main_m365.py` arranca y expone `GET /api/messages` con `200`.
- [ ] `POST /api/messages` con Activity válida + `expectReplies` devuelve respuesta del agente.
- [ ] Comandos `/help` y `/clear` funcionan por canal runtime.

### B. Robustez

- [ ] Mensaje vacío devuelve respuesta controlada (sin excepciones no gestionadas).
- [ ] Requests con payload incompleto generan error esperado y trazable.
- [ ] No hay doble inicialización del agente en concurrencia (`_ensure_started` + lock).

### C. Seguridad/identidad

- [ ] `az login` activo y contexto correcto para pruebas locales con Foundry.
- [ ] No se usan secretos hardcodeados en código.
- [ ] Configuración de app registration (`MICROSOFT_APP_ID`, `...PASSWORD`, `...TENANTID`) presente en `.env`.

### D. Observabilidad operativa mínima

- [ ] Logs suficientes para identificar Activity inválida, errores de callback y errores de modelo.
- [ ] Errores críticos se reproducen con caso de prueba documentado.

### E. Preparación para Fase 3

- [ ] Decidida estrategia de endpoint público (Dev Tunnel inicial -> App Service objetivo).
- [ ] Confirmado que pruebas manuales locales son estables antes de wiring con canal real.

### F. Validación con Microsoft 365 Agents Playground

- [ ] Playground instalado y operativo en el equipo de desarrollo.
- [ ] Conexión del Playground al endpoint `http://127.0.0.1:3978/api/messages` validada.
- [ ] Casos de uso funcionales ejecutados en Playground (welcome, `/help`, `/clear`, mensaje normal).
- [ ] Casos negativos ejecutados (payload inválido, mensajes vacíos, errores de inicialización).

---

## 13) Microsoft 365 Agents Playground (preproducción local)

El Playground es la herramienta recomendada para validar el runtime del agente con un cliente que simula comportamiento de canal, sin ir aún a publicación productiva.

### 13.1 Objetivo

- Probar el endpoint `/api/messages` con un emulador de actividades realista.
- Verificar flujo de eventos (`conversationUpdate`, `message`, etc.) sin fabricar todos los payloads manualmente.
- Detectar problemas de integración antes de Fase 3 (publicación/canal real).

### 13.2 Dependencias previas

#### Dependencias de Node.js

- Node.js LTS instalado (incluye `npm`).
- Verificación:

```powershell
node --version
npm --version
```

#### Dependencias Python del agente

- Entorno virtual activo para este proyecto.
- Dependencias del módulo instaladas:

```powershell
pip install -r requirements.txt
```

### 13.3 Instalación de Playground

Instalación global (recomendada para pruebas locales rápidas):

```powershell
npm install -g @microsoft/teams-app-test-tool
```

Comando de arranque:

```powershell
teamsapptester
```

### 13.4 Arranque mínimo de extremo a extremo

#### Terminal 1 - Servidor del agente

```powershell
cd .
python .\main_m365.py
```

#### Terminal 2 - Playground

```powershell
teamsapptester
```

El Playground abrirá una UI web local y esperará endpoint.

### 13.5 Parametrización recomendada

Configura (o verifica) en Playground:

- Endpoint del agente: `http://127.0.0.1:3978/api/messages`
- Canal simulado: `msteams` (si está disponible en configuración)
- Locale/zona horaria de prueba según el caso (`es-ES` / `Europe/Madrid`, etc.)

Si el endpoint no está disponible, valida primero:

```powershell
Invoke-RestMethod -Uri "http://localhost:3978/api/messages" -Method Get
```

### 13.6 Catálogo de casos de uso (sugerido)

#### Casos funcionales

1. Alta de conversación (`membersAdded`) -> mensaje de bienvenida.
2. Comando `/help` -> texto de ayuda.
3. Comando `/clear` -> reinicio de contexto.
4. Pregunta normal -> respuesta de Foundry.

#### Casos de robustez

1. Mensaje vacío -> respuesta controlada.
2. Mensaje largo (>= 1.500 caracteres) -> respuesta sin error.
3. Varias preguntas seguidas -> contexto estable.

#### Casos negativos

1. Endpoint parado -> comprobar error esperado de conexión.
2. Puerto ocupado -> validar diagnóstico (`Errno 10048`).
3. Sesión Azure no válida (`az login` ausente/expirada) -> error de token trazable.

### 13.7 Criterio de salida con Playground

Puedes considerar lista la preproducción local cuando:

- Todos los casos funcionales pasan.
- Los casos negativos generan errores esperados y comprensibles.
- No hay errores no controlados en logs del servidor.
- El flujo manual con `Invoke-RestMethod` y el flujo con Playground son consistentes.
