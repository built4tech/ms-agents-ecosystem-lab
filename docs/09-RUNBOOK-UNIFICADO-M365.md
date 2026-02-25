# Runbook unificado M365 — CLI + Local + Túnel + Infra + Cloud

Runbook maestro para ejecutar validaciones operativas end-to-end en un único documento, manteniendo el detalle completo de los runbooks existentes.

## Estado de este documento

- Este runbook unifica y conserva el detalle de:
  - `03-RUNBOOK-PREFASE3-M365.md`
  - `04-RUNBOOK-FASE3-LOCAL-TUNEL-M365.md`
  - `07-RUNBOOK-PRUEBAS-CLI-PLAYGROUND-CLOUD.md`
  - `08-RUNBOOK-E2E-CLI-INFRA-PLAYGROUND-CLOUD.md`
- Los documentos fuente se mantienen en `docs/` para trazabilidad histórica.

---

## 0) Prerrequisitos globales

- PowerShell en la raíz del repo.
- `.venv` creado e instalado con `requirements.txt`.
- `az login` activo en la suscripción correcta.
- `teamsapptester` instalado.
- Si aplica infraestructura: `infra/config/lab-config.ps1` configurado.
- `.env` en raíz con variables de Foundry y canal M365.

Comprobación rápida:

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
az account show --output table
python --version
node --version
npm --version
teamsapptester --version
```

Instalación de dependencias (si faltan):

```powershell
pip install -r requirements.txt
npm install -g @microsoft/teams-app-test-tool
```

Si el entorno es nuevo (sin Foundry/RG), bootstrap base:

```powershell
Set-Location .\infra\scripts
.\deploy-all.ps1
```

`deploy-all.ps1` ejecuta `auth-permissions-helper.ps1` al inicio para validar login, subscription y permisos RBAC/Entra antes de continuar.

---

## 1) Variables operativas recomendadas

```powershell
$repo = "c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab"
$appLocal = "http://127.0.0.1:3978/api/messages"
$appCloud = "https://wapp-agent-identities-viewer.azurewebsites.net/api/messages"
```

---

## 2) Validación pre-Fase 3 (Go/No-Go base)

## 2.1 Smoke test CLI

```powershell
Set-Location "$repo"
"exit" | python .\main.py cli
```

PASS esperado:
- Arranca sin excepción.
- Sale limpio con `exit`.

## 2.2 Arranque runtime M365

```powershell
Set-Location "$repo"
python .\main_m365.py
```

Si falla con puerto ocupado (`Errno 10048`): cerrar proceso previo o cambiar `PORT` en `.env`.

## 2.3 Health-check endpoint

```powershell
Invoke-RestMethod -Uri "http://localhost:3978/api/messages" -Method Get
```

En Fase 3 puede responder `401` por enforcement de auth. El estado esperado funcional del runbook es endpoint operativo y protegido.

## 2.4 POST funcional manual (expectReplies)

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
  text = 'Quien es Cristobal Colon'
  deliveryMode = 'expectReplies'
} | ConvertTo-Json -Depth 8

Invoke-RestMethod -Uri "http://localhost:3978/api/messages" -Method Post -ContentType "application/json" -Body $body | ConvertTo-Json -Depth 10
```

PASS esperado:
- Respuesta con `activities`.
- Al menos una actividad `message` con texto del agente.

## 2.5 Playground local básico

```powershell
teamsapptester
```

Configurar endpoint:
- `http://127.0.0.1:3978/api/messages`

Casos mínimos:
1. `membersAdded` (bienvenida)
2. `/help`
3. `/clear`
4. mensaje normal

---

## 3) Validación Fase 3 local + túnel

## 3.1 Confirmar identidad Azure

```powershell
az account show --output table
```

## 3.2 Regresión CLI local

```powershell
Set-Location "$repo"
"exit" | .\.venv\Scripts\python.exe .\main.py cli
```

## 3.3 Arrancar runtime M365 autenticado

```powershell
Set-Location "$repo"
.\.venv\Scripts\python.exe .\main_m365.py
```

OK esperado: `Running on http://localhost:3978`.

## 3.4 Verificar endpoint protegido

```powershell
$r = Invoke-WebRequest -Uri "http://localhost:3978/api/messages" -Method Get -SkipHttpErrorCheck
"HTTP_STATUS=$($r.StatusCode)"
```

PASS esperado: `401`.

## 3.5 Cargar variables de `.env` en sesión actual

```powershell
Set-Location "$repo"
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
  if ($_ -match '^\s*([^=]+)=(.*)$') {
    [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
  }
}
```

Validar presencia de credenciales de canal:

```powershell
@('MICROSOFT_APP_ID','MICROSOFT_APP_PASSWORD','MICROSOFT_APP_TENANTID') | ForEach-Object {
  $name = $_
  $value = [Environment]::GetEnvironmentVariable($name, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) { "$name=MISSING" } else { "$name=SET" }
}
```

## 3.6 Playground local autenticado

```powershell
$cid = $env:MICROSOFT_APP_ID
$cs = $env:MICROSOFT_APP_PASSWORD
$tid = $env:MICROSOFT_APP_TENANTID

if ([string]::IsNullOrWhiteSpace($cid) -or [string]::IsNullOrWhiteSpace($cs) -or [string]::IsNullOrWhiteSpace($tid)) {
  throw "Faltan variables MICROSOFT_APP_ID / MICROSOFT_APP_PASSWORD / MICROSOFT_APP_TENANTID en esta sesión"
}

teamsapptester start -e http://127.0.0.1:3978/api/messages --channel-id msteams --delivery-mode expectReplies --cid $cid --cs $cs --tid $tid
```

PASS esperado: `/help`, `/clear`, mensaje libre responden correctamente.

## 3.7 Exponer endpoint por Dev Tunnel

```powershell
devtunnel user login --entra --use-browser-auth
devtunnel host -p 3978 --allow-anonymous
```

Probar Playground contra túnel:

```powershell
teamsapptester start -e https://<tu-subdominio>/api/messages --channel-id msteams --delivery-mode expectReplies --cid $env:MICROSOFT_APP_ID --cs $env:MICROSOFT_APP_PASSWORD --tid $env:MICROSOFT_APP_TENANTID
```

Si `devtunnel` no existe:

```powershell
winget install --id Microsoft.devtunnel -e --accept-package-agreements --accept-source-agreements
```

Fallback (sin reiniciar terminal):

```powershell
C:/Users/carlosmu/AppData/Local/Microsoft/WinGet/Packages/Microsoft.devtunnel_Microsoft.Winget.Source_8wekyb3d8bbwe/devtunnel.exe host -p 3978 --allow-anonymous
```

---

## 4) Infra + despliegue cloud (flujo E2E)

## 4.1 Crear Service Principal multitenant (M365)

```powershell
Set-Location .\infra\scripts
.\03-m365-service-principal.ps1
```

PASS esperado:
- `.env.generated` con `MICROSOFT_APP_ID`, `MICROSOFT_APP_PASSWORD`, `MICROSOFT_APP_TYPE`, `MICROSOFT_APP_TENANTID`.

## 4.2 Crear observabilidad

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab/infra/scripts
.\04-observability.ps1
```

PASS esperado:
- `.env.generated` con `APPLICATIONINSIGHTS_CONNECTION_STRING`, `ENABLE_OBSERVABILITY`, `ENABLE_A365_OBSERVABILITY_EXPORTER`, `OTEL_SERVICE_NAME`, `OTEL_SERVICE_NAMESPACE`.

## 4.3 Consolidar `.env` para despliegue

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab/infra/scripts
.\01-resource-group.ps1
.\02-foundry-maf.ps1
.\03-m365-service-principal.ps1
.\04-observability.ps1
```

Nota: los scripts `01` a `05` invocan automáticamente `auth-permissions-helper.ps1` y paran la ejecución cuando faltan permisos requeridos.

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
Copy-Item .\.env.generated .\.env -Force
```

## 4.4 Crear/configurar App Service

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab/infra/scripts
.\05-webapp-m365.ps1
```

## 4.5 Generar manifest + desplegar código

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
.\dist\dev\build-m365-manifest.ps1
```

PASS esperado:
- `dist/m365-manifest/staging/manifest.json`
- `dist/m365-manifest/<project>-m365-manifest.zip`
- `dist/deploy/<project>-appservice-<timestamp>.zip`
- Deployment a App Service completado.

---

## 5) Pruebas en entorno cloud

## 5.1 Smoke HTTP

```powershell
$appCloud = "https://wapp-agent-identities-viewer.azurewebsites.net/api/messages"
$r = Invoke-WebRequest -Uri $appCloud -Method Get -SkipHttpErrorCheck
"HTTP_STATUS=$($r.StatusCode)"
```

PASS esperado: `401` o `405` (no `503`, no timeout).

## 5.2 Estado de deployment

```powershell
az webapp log deployment list --resource-group rg-agents-lab --name wapp-agent-identities-viewer --query "[0:5].{id:id,status:status,message:message,received:received_time}" -o table
```

## 5.3 Descarga de logs runtime

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
$out = ".\dist\dev\wapp-logs-runbook.zip"
$dest = ".\dist\dev\wapp-logs-runbook"
if (Test-Path $out) { Remove-Item $out -Force }
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
az webapp log download --resource-group rg-agents-lab --name wapp-agent-identities-viewer --log-file $out --output none
Expand-Archive -Path $out -DestinationPath $dest
Get-ChildItem "$dest/LogFiles/*_default_docker.log" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 |
  ForEach-Object { Select-String -Path $_.FullName -Pattern 'Traceback|ERROR|Exception|Running on|Listening' | Select-Object -Last 120 }
```

## 5.4 Playground contra cloud

```powershell
teamsapptester start -e https://wapp-agent-identities-viewer.azurewebsites.net/api/messages --channel-id msteams --delivery-mode expectReplies --cid $env:MICROSOFT_APP_ID --cs $env:MICROSOFT_APP_PASSWORD --tid $env:MICROSOFT_APP_TENANTID
```

Casos mínimos:
- `/help`
- `/clear`
- mensaje libre

## 5.5 Validación en Copilot (tenant) — criterio de cierre Fase 3

Objetivo: verificar el criterio de salida del plan: **el agente aparece en Copilot y responde mensajes básicos end-to-end**.

Pasos mínimos:
1. Cargar/actualizar el manifest generado (`dist/m365-manifest/<project>-m365-manifest.zip`) en el tenant de destino.
2. Confirmar en el catálogo del tenant que la app/agente está visible para el usuario de prueba.
3. Abrir Copilot (scope del tenant) y localizar el agente.
4. Ejecutar al menos 3 interacciones:
  - saludo
  - `/help` (o comando equivalente expuesto)
  - mensaje libre de negocio
5. Verificar respuesta funcional end-to-end y ausencia de error de canal/autenticación.

Evidencia mínima requerida:
- Captura de presencia del agente en Copilot.
- Captura o transcript de 3 interacciones exitosas.
- Marca temporal + usuario/tenant de prueba.

---

## 6) Casos negativos obligatorios

## 6.1 Payload inválido

Enviar body incompleto (por ejemplo sin `type`) y verificar error trazable.

PASS esperado: error controlado en logs con diagnóstico claro.

## 6.2 Playground sin credenciales

Ejecutar `teamsapptester start` sin `--cid/--cs/--tid`.

PASS esperado: rechazo de autorización (`401`) y diagnóstico explícito.

## 6.3 Token inválido/expirado

Simular sesión sin contexto válido de Azure CLI.

PASS esperado: error explícito de identidad/token, sin bloqueo total de proceso.

## 6.4 Runtime no disponible

Detener runtime local y repetir pruebas B2/B3 equivalentes.

PASS esperado: error de conexión claro y trazable.

---

## 7) Plantilla de resultados

| ID | Superficie | Caso | Resultado | Evidencia | Observaciones |
| --- | --- | --- | --- | --- | --- |
| A1 | CLI | Arranque + exit | PASS/FAIL | Consola | |
| A2 | CLI | Turnos + clear | PASS/FAIL | Consola | |
| B1 | Local runtime | Startup | PASS/FAIL | Log consola | |
| B2 | Local runtime | GET sin token | PASS/FAIL | HTTP status | |
| B3 | Playground local | 4 casos | PASS/FAIL | Captura/log | |
| B4 | Playground túnel | 3 casos | PASS/FAIL | Captura/log | |
| C1 | Cloud | Smoke HTTP | PASS/FAIL | HTTP status | |
| C2 | Cloud | Deployment status | PASS/FAIL | Tabla az | |
| C3 | Cloud | Logs startup | PASS/FAIL | Extracto logs | |
| C4 | Cloud | Playground E2E | PASS/FAIL | Captura/log | |
| D1 | Negativo | Payload inválido | PASS/FAIL | Log error | |
| D2 | Negativo | Sin credenciales | PASS/FAIL | Error esperado | |
| D3 | Negativo | Token inválido | PASS/FAIL | Error esperado | |
| D4 | Negativo | Runtime caído | PASS/FAIL | Error esperado | |

---

## 8) Criterio final GO / NO-GO

GO:
- CLI local PASS.
- Playground local PASS.
- Playground túnel PASS.
- Scripts `01`, `02`, `03`, `04`, `05` PASS.
- Manifest + ZIP generado en `dist/m365-manifest`.
- Deploy cloud PASS y endpoint estable.
- Casos negativos con error esperado y trazable.
- Validación Copilot tenant PASS (`aparece + responde end-to-end`).

NO-GO:
- `503` o timeout en cloud.
- Tracebacks recurrentes en startup/runtime.
- Fallo en `/help`, `/clear` o mensaje normal en Playground (local/túnel/cloud).
- Errores de identidad no diagnosticados.
- El agente no aparece en Copilot del tenant o no responde end-to-end.

---

## 9) Frecuencia sugerida

- Antes de cada despliegue cloud: A1, B1, B2.
- Después de cada despliegue: C1, C2, C3, C4.
- Cierre de sprint/release: ejecución completa de A+B+C+D.
