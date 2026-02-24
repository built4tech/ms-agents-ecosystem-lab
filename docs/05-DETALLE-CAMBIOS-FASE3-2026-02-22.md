# Detalle técnico de cambios — Fase 3 (2026-02-22)

## Propósito

Este documento explica en detalle qué cambios se incorporaron durante la ejecución de Fase 3, cómo funciona el flujo nuevo de ejecución, qué llamadas se realizan y qué parte de la fase queda pendiente.

---

## Alcance real implementado en esta iteración

### Objetivos de Fase 3 del plan

1. Crear/usar app registration + Azure Bot Service.
2. Configurar secretos/credenciales en entorno.
3. Generar o adaptar manifest M365 Copilot y empaquetar `.zip`.
4. Desplegar endpoint público (App Service/Container Apps u otro hosting).

### Estado real

- **Objetivo 1: parcial**
  - Se **usa app registration existente** para autenticación de canal en runtime local y pruebas por Playground.
  - **Azure Bot Service** no quedó desplegado/configurado en esta iteración.
- **Objetivo 2: completado en entorno local/dev**
  - Se implementó carga y validación de `MICROSOFT_APP_ID`, `MICROSOFT_APP_PASSWORD`, `MICROSOFT_APP_TENANTID`.
  - Se integra `MsalConnectionManager` + `CloudAdapter` autenticado.
- **Objetivo 3: pendiente**
- **Objetivo 4: pendiente**

Conclusión: **Fase 3 queda en progreso**. No se debe avanzar a Fase 4 hasta completar 3 y 4.

---

## Cambios de código incorporados

### 1) Nuevo módulo de autenticación de canal

Archivo: `platforms/maf/01-simple-chat/app/channels/m365_auth.py`

Responsabilidad:
- Cargar `.env` raíz.
- Requerir variables de credenciales de app (`MICROSOFT_APP_*`).
- Construir:
  - `AgentAuthConfiguration` (usada por middleware JWT)
  - `MsalConnectionManager` (conexión `SERVICE_CONNECTION`)
  - `CloudAdapter(connection_manager=...)`

Punto clave:
- Si falta una variable requerida, el proceso falla temprano con error explícito (`ValueError`) para evitar arranques inseguros.

### 2) Entry point M365 actualizado

Archivo: `platforms/maf/01-simple-chat/main_m365.py`

Antes:
- Arrancaba con `AGENT_APP` por defecto y `auth_configuration=None`.

Ahora:
- `create_m365_auth_runtime()` crea adapter y auth config.
- `create_agent_application(adapter=adapter)` inyecta adapter autenticado.
- `start_server(agent_app, auth_configuration)` arranca con middleware JWT activo y configuración válida.

### 3) Factory para app de canal

Archivo: `platforms/maf/01-simple-chat/app/channels/m365_app.py`

Cambio:
- Se añade `create_agent_application(adapter: CloudAdapter | None)` para soportar inyección de adapter autenticado.
- Se mantiene la misma lógica funcional de handlers (`membersAdded`, `/help`, `message`) y reutilización de `ChatService`.

Objetivo del cambio:
- Mantener arquitectura existente (sin rediseño) y habilitar auth de Fase 3 de manera incremental.

### 4) Servidor HTTP sin cambio de diseño

Archivo: `platforms/maf/01-simple-chat/app/channels/start_server.py`

Se mantiene:
- Middleware `jwt_authorization_middleware`.
- Rutas `POST /api/messages` y `GET /api/messages`.

Comportamiento con Fase 3 activa:
- Sin `Authorization`, `GET/POST` directos devuelven `401`.

---

## Flujo nuevo de ejecución (paso a paso)

## A. Arranque runtime M365

1. `main_m365.py` llama `create_m365_auth_runtime()`.
2. `m365_auth.py`:
   - carga `/.env`
   - valida `MICROSOFT_APP_ID/PASSWORD/TENANTID`
   - crea `AgentAuthConfiguration`
   - crea `MsalConnectionManager`
   - crea `CloudAdapter` autenticado
3. `main_m365.py` crea `AgentApplication` con ese adapter.
4. `start_server()` levanta `aiohttp` con `jwt_authorization_middleware`.

## B. Procesamiento de request entrante

1. Llega request a `POST /api/messages`.
2. Middleware JWT valida token:
   - con token válido → pasa al handler
   - sin token → `401`
3. `start_agent_process()` transforma request Activity y enruta por `AgentApplication`.
4. Handler `@activity("message")`:
   - asegura inicialización (`_ensure_started`)
   - procesa comandos (`/help`, `/clear`, etc.)
   - delega en `ChatService.ask(...)`
5. `ChatService` llama `SimpleChatAgent` (Foundry con `AzureCliCredential` en local CLI path).

---

## Llamadas relevantes implementadas

### Llamadas internas de runtime

- `create_m365_auth_runtime()`
- `AgentAuthConfiguration(...)`
- `MsalConnectionManager(CONNECTIONS={"SERVICE_CONNECTION": ...})`
- `CloudAdapter(connection_manager=...)`
- `start_server(agent_app, auth_configuration)`
- `start_agent_process(req, agent, adapter)`
- `chat_service.ask(text)`

### Llamadas operativas de validación (runbook)

- CLI local:
  - `.../.venv/Scripts/python.exe .\main.py`
- Runtime canal:
  - `.../.venv/Scripts/python.exe .\main_m365.py`
- Playground local:
  - `teamsapptester start -e <endpoint> --cid ... --cs ... --tid ...`
- Túnel:
  - `devtunnel user login --entra --use-browser-auth`
  - `devtunnel host -p 3978 --allow-anonymous`

---

## Resultado funcional observado

- Se mantienen pruebas locales de CLI (sin romper `AzureCliCredential` del core).
- Endpoint de canal deja de aceptar invocación anónima directa (`401` esperado).
- Playground con credenciales de app y túnel puede enviar `Authorization: Bearer` al endpoint.

Advertencia no bloqueante observada:
- Mensajes de iKey inválida en telemetría interna de `teamsapptester`.
- No bloquea autenticación/flujo de negocio del agente.

---

## Qué NO se implementó aún (pendiente Fase 3)

1. **Manifest M365 Copilot** (`.zip`) listo para publicación (objetivo 3).
2. **Despliegue endpoint público productivo** en App Service/Container Apps (objetivo 4).
3. Integración completa con Azure Bot Service en entorno publicado.

---

## Criterio para cerrar Fase 3

La fase solo se considera completada cuando:

- Objetivo 3: manifest generado/adaptado y validado.
- Objetivo 4: endpoint desplegado públicamente y conectado al canal objetivo.
- Validación end-to-end en canal M365/Copilot sobre endpoint publicado.

Hasta entonces, el estado correcto es: **Fase 3 en progreso**.
