# 12 - CAMBIOS BOT SERVICE + ENDPOINT + MSTEAMS (2026-03-04)

## 1) Contexto

La aplicación ya estaba operativa en runtime cloud (Web App y endpoint `/api/messages` funcionando en pruebas directas), pero en Copilot/Teams **no llegaba actividad**.

Síntoma observado:
- El agente aparece en Copilot/Teams.
- Al ejecutar prompts desde Copilot, no hay entradas `POST /api/messages` en el backend.

Diagnóstico:
- El `manifest.zip` era válido (`version`, `id`, `botId`, `validDomains` y `scopes` correctos).
- Faltaba el recurso de enrutamiento en Azure Bot Service, por lo que no existía camino de entrega entre Copilot/Teams y la Web App.

---

## 2) Objetivo de los cambios

1. Automatizar la persistencia del endpoint público del bot tras crear/validar la Web App.
2. Garantizar que `validDomains` se actualiza de forma consistente en **ambos** manifiestos:
   - `manifest.json`
   - `agenticUserTemplateManifest.json`
3. Documentar formalmente la creación/configuración del bot `bot-agent-identities-viewer` y la habilitación de `MsTeamsChannel`.

---

## 3) Fundamento técnico

Para que un agente custom engine funcione en Copilot/Teams, se necesitan tres capas alineadas:

1. **Runtime** (Web App): endpoint HTTP real (`https://<host>/api/messages`).
2. **Bot Service registration**: recurso Azure Bot Service que conoce `AppId` y `endpoint`.
3. **Manifiesto M365**: metadatos de la app con `validDomains` y IDs correctos.

Si la capa 2 no existe o apunta mal, Copilot/Teams no puede enrutar actividades al runtime.

---

## 4) Cambios en scripts

## 4.1 `infra/scripts/05-webapp-m365.ps1`

Se amplió la actualización de `.env.generated` para que no solo guarde `WEB_APP_NAME`, sino también:

- `AGENT_MESSAGES_ENDPOINT=https://<webapp>.azurewebsites.net/api/messages`
- `AGENT_VALID_DOMAIN=<webapp>.azurewebsites.net`

Además, estos valores se muestran en salida de consola con `Write-Endpoint`, facilitando verificación inmediata.

### Motivación

Evitar que `validDomains` dependa de edición manual o de valores locales (`localhost`) al preparar publicación cloud.

---

## 4.2 `infra/scripts/env-generated-helper.ps1`

Se añadieron claves nuevas al modelo de `.env.generated`:

- `AGENT_MESSAGES_ENDPOINT`
- `AGENT_VALID_DOMAIN`

Y se incorporaron al bloque de sección `05-webapp-m365.ps1` del contenido generado.

### Motivación

Mantener trazabilidad en `.env.generated` de los valores de publicación M365 derivados de infraestructura real.

---

## 4.3 `.env.example`

Se actualizaron ejemplos del bloque Web App con:

- `AGENT_MESSAGES_ENDPOINT`
- `AGENT_VALID_DOMAIN`

### Motivación

Documentar para nuevos despliegues qué variables se esperan y el formato correcto (endpoint completo vs dominio).

---

## 4.4 `dist/dev/build-m365-manifest.ps1`

Se reforzó la resolución de dominio válido con prioridad:

1. `AGENT_VALID_DOMAIN`
2. Host derivado de `AGENT_MESSAGES_ENDPOINT`
3. fallback a `AGENT_HOST`

Se añadieron funciones:
- `Resolve-ValidDomain`
- `Set-ManifestValidDomains`

Y se fuerza explícitamente `validDomains` en ambos archivos de salida:
- `manifest.json`
- `agenticUserTemplateManifest.json`

### Motivación

Blindar el build frente a desalineaciones por ediciones manuales previas o divergencia entre plantillas/salidas.

---

## 4.5 `infra/scripts/06-bot-service.ps1`

Se incorpora un nuevo script operativo para cerrar el gap entre “runtime funcionando” y “canal Copilot/Teams enrutable”.

### Objetivo detallado del script

El objetivo de `06-bot-service.ps1` es **materializar y mantener** la capa de enrutamiento de canal en Azure, de forma idempotente y alineada con el estado real de la Web App.

En términos prácticos, el script asegura que:

1. Exista un recurso `Microsoft.BotService/botServices` para el agente.
2. Ese bot esté enlazado al `MICROSOFT_APP_ID` correcto.
3. El endpoint de mensajería del bot apunte al runtime cloud (`https://<webapp>.azurewebsites.net/api/messages`).
4. El canal `MsTeamsChannel` esté habilitado.
5. Quede persistido en `.env.generated` el estado mínimo operativo (`BOT_SERVICE_NAME`, `AGENT_MESSAGES_ENDPOINT`, `AGENT_VALID_DOMAIN`).

### Problema que resuelve

Resuelve el escenario donde:
- La app aparece en Copilot/Teams,
- El manifiesto es válido,
- Pero **no llega actividad** al backend.

Ese síntoma suele implicar que falta o está mal configurada la capa de Bot Service (registro inexistente, endpoint antiguo o canal Teams no habilitado).

### Entradas y dependencias

El script depende de:
- `MICROSOFT_APP_ID` y `MICROSOFT_APP_TENANTID` en `.env`.
- `WEB_APP_NAME` o `AGENT_MESSAGES_ENDPOINT` para resolver destino.
- `Resource Group` existente.
- Azure CLI autenticado y con permisos de escritura en recursos.

También registra automáticamente el proveedor `Microsoft.BotService` si no estaba registrado.

### Reglas de configuración del endpoint

Orden de resolución del endpoint:

1. Si existe `AGENT_MESSAGES_ENDPOINT`, se usa tal cual.
2. Si no existe, se consulta `WEB_APP_NAME` y se deriva `https://<defaultHostName>/api/messages`.

Con esto se evita hardcode manual en comandos y se minimiza drift entre infraestructura y configuración de canal.

### Política de tipo de aplicación

Para creación nueva se usa `SingleTenant`.

Motivación:
- La creación `MultiTenant` en Bot Service está deprecada para nuevos recursos.
- `SingleTenant` evita fallo de aprovisionamiento (`InvalidBotCreationData`) en el flujo actual.

### Comportamiento idempotente

El script está diseñado para poder ejecutarse múltiples veces:

- Si el bot no existe: lo crea.
- Si existe: valida AppId y actualiza endpoint.
- Si `MsTeamsChannel` no existe: lo crea.
- Si ya existe: no rompe estado, solo confirma.

### Persistencia de salidas

Se actualiza `.env.generated` con:

- `BOT_SERVICE_NAME`
- `AGENT_MESSAGES_ENDPOINT`
- `AGENT_VALID_DOMAIN`

Así el resto de scripts (build de manifiesto/publicación) reutiliza estos valores y reduce configuración manual.

### Resultado operativo esperado

Tras ejecutar `06-bot-service.ps1`:

1. Copilot/Teams tiene ruta válida hacia `/api/messages`.
2. Los logs de Web App deben empezar a mostrar tráfico `POST /api/messages` al invocar el agente.
3. El estado queda documentado en `.env.generated` para siguientes ejecuciones.

---

## 5) Creación del bot `bot-agent-identities-viewer`

## 5.1 Motivación

Sin recurso Bot Service no hay routing desde Copilot/Teams al endpoint del runtime, aunque el manifiesto y la Web App sean correctos.

## 5.2 Objetivo

Registrar un bot en Azure que use:
- `MICROSOFT_APP_ID` ya existente
- Endpoint de producción `https://wapp-agent-identities-viewer.azurewebsites.net/api/messages`
- Canal Teams habilitado

## 5.3 Configuración aplicada

Recurso creado:
- Nombre: `bot-agent-identities-viewer`
- Resource Group: `rg-agents-lab`
- Kind: `azurebot`
- SKU: `F0`
- Location: `global`
- App Type: `SingleTenant`
- Endpoint: `https://wapp-agent-identities-viewer.azurewebsites.net/api/messages`

> Nota operativa: Azure rechazó creación `MultiTenant` para recursos nuevos (`InvalidBotCreationData`). Se usó `SingleTenant` por requisito actual del servicio.

---

## 6) Método para habilitar `MsTeamsChannel`

Comando usado:

```powershell
az bot msteams create -g rg-agents-lab -n bot-agent-identities-viewer
```

Verificación:

```powershell
az bot msteams show -g rg-agents-lab -n bot-agent-identities-viewer
```

### Motivación

Habilitar explícitamente canal Teams para que actividades iniciadas desde Teams/Copilot puedan ser enrutadas mediante Bot Service.

---

## 7) Validación recomendada post-cambios

1. Regenerar manifiesto:

```powershell
./dist/dev/build-m365-manifest.ps1 -SkipWebAppDeploy
```

2. Verificar `validDomains` en ambos manifiestos:

```powershell
$manifest = Get-Content ./dist/deploy/m365/manifest/manifest.json -Raw | ConvertFrom-Json
$agentic  = Get-Content ./dist/deploy/m365/manifest/agenticUserTemplateManifest.json -Raw | ConvertFrom-Json
$manifest.validDomains
$agentic.validDomains
```

3. Publicar `dist/deploy/m365/package/manifest.zip`.
4. Ejecutar prueba en Copilot/Teams con `az webapp log tail` activo y comprobar tráfico `POST /api/messages`.

---

## 8) Resultado esperado

Con estos cambios:
- El endpoint cloud queda persistido automáticamente en variables de entorno.
- `validDomains` queda consistente en ambos manifiestos de publicación.
- El bot registrado en Azure + Teams channel habilitado proporciona la ruta de entrega de actividad hacia la Web App.

Esto elimina los puntos de fallo detectados en el incidente de “agente visible pero sin actividad entrante”.

---

## 9) Integración en `deploy-all.ps1`

Se integró `06-bot-service.ps1` en el flujo de `deploy-all.ps1` como paso **post-05** con confirmación explícita.

### Comportamiento

1. `deploy-all` ejecuta fases 01..05 como hasta ahora.
2. Tras sincronizar `.env.generated -> .env` post-05, solicita confirmación para ejecutar 06.
3. Si el usuario confirma (`y/Y`):
   - ejecuta `06-bot-service.ps1` en modo no interactivo (`RUNNING_FROM_DEPLOY_ALL=1`),
   - vuelve a sincronizar `.env.generated -> .env` post-06.
4. Si el usuario no confirma, el paso 06 se omite sin fallo del despliegue base.

### Motivación de diseño

- Mantener compatibilidad con flujos previos donde el runtime cloud era suficiente.
- Permitir cerrar en una sola corrida el enrutamiento Copilot/Teams cuando se desea.
- Conservar trazabilidad y control humano antes de crear/modificar recursos de canal.
