# Runbook E2E — CLI + Infra + Playground + Cloud

Runbook operativo completo para validar el proyecto de extremo a extremo con orden lógico y repetible.

## 0) Prerrequisitos

- PowerShell en la raíz del repo.
- `.venv` creado e instalado con `requirements.txt`.
- `az login` activo en la suscripción correcta.
- `teamsapptester` instalado.
- Archivo `infra/config/lab-config.ps1` configurado.

Comprobación rápida:

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
az account show --output table
python --version
teamsapptester --version
```

Si el entorno es nuevo (sin Foundry/RG), ejecuta bootstrap base antes del paso 1:

```powershell
Set-Location .\infra\scripts
.\deploy-all.ps1
```

`deploy-all.ps1` ejecuta primero `auth-permissions-helper.ps1` para validar sesión y permisos antes de crear recursos.

---

## 1) Prueba CLI local (primero)

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
"exit" | .\.venv\Scripts\python.exe .\main.py cli
```

PASS esperado:
- Arranca sin excepción.
- Sale limpio con `exit`.

---

## 2) Crear Service Principal multitenant (M365)

```powershell
Set-Location .\infra\scripts
.\03-m365-service-principal.ps1
```

PASS esperado:
- `.env.generated` actualizado con:
  - `MICROSOFT_APP_ID`
  - `MICROSOFT_APP_PASSWORD`
  - `MICROSOFT_APP_TYPE`
  - `MICROSOFT_APP_TENANTID`

---

## 3) Web local + Playground local

### 3.1 Cargar variables desde `.env`

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
  if ($_ -match '^\s*([^=]+)=(.*)$') {
    [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
  }
}
```

### 3.2 Arrancar runtime M365 local

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
.\.venv\Scripts\python.exe .\main.py
```

### 3.3 Validación de endpoint protegido

```powershell
$r = Invoke-WebRequest -Uri "http://localhost:3978/api/messages" -Method Get -SkipHttpErrorCheck
"HTTP_STATUS=$($r.StatusCode)"
```

PASS esperado: `401`.

### 3.4 Playground local autenticado

Valida primero que las variables están presentes en la sesión actual:

```powershell
@('MICROSOFT_APP_ID','MICROSOFT_APP_PASSWORD','MICROSOFT_APP_TENANTID') | ForEach-Object {
  $name = $_
  $value = [Environment]::GetEnvironmentVariable($name, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) { "$name=MISSING" } else { "$name=SET" }
}
```

Si alguna aparece como `MISSING`, vuelve al paso 3.1 o copia primero `.env.generated` a `.env` y recarga variables.

Ejecuta Playground usando variables intermedias (evita pasar flags vacíos):

```powershell
$cid = $env:MICROSOFT_APP_ID
$cs = $env:MICROSOFT_APP_PASSWORD
$tid = $env:MICROSOFT_APP_TENANTID

if ([string]::IsNullOrWhiteSpace($cid) -or [string]::IsNullOrWhiteSpace($cs) -or [string]::IsNullOrWhiteSpace($tid)) {
  throw "Faltan variables MICROSOFT_APP_ID / MICROSOFT_APP_PASSWORD / MICROSOFT_APP_TENANTID en esta sesión"
}

teamsapptester start -e http://localhost:3978/api/messages --channel-id msteams --delivery-mode expectReplies --cid $cid --cs $cs --tid $tid

# Alternativa recomendada para evitar problemas de loopback en algunos entornos:
# teamsapptester start -e http://127.0.0.1:3978/api/messages --channel-id msteams --delivery-mode expectReplies --cid $cid --cs $cs --tid $tid
```

Casos mínimos:
- `/help`
- `/clear`
- mensaje libre

---

## 4) Web local + Playground por Dev Tunnel

### 4.1 Login de túnel

```powershell
devtunnel user login --entra --use-browser-auth
```

### 4.2 Exponer puerto local 3978

```powershell
devtunnel host -p 3978 --allow-anonymous
```

### 4.3 Probar Playground contra endpoint del túnel

```powershell
teamsapptester start -e https://<tu-subdominio>/api/messages --channel-id msteams --delivery-mode expectReplies --cid $env:MICROSOFT_APP_ID --cs $env:MICROSOFT_APP_PASSWORD --tid $env:MICROSOFT_APP_TENANTID
```

PASS esperado: respuestas correctas en `/help`, `/clear` y mensaje libre.

---

## 5) Crear observabilidad

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab/infra/scripts
.\04-observability.ps1
```

PASS esperado:
- `.env.generated` actualizado con:
  - `APPLICATIONINSIGHTS_CONNECTION_STRING`
  - `ENABLE_OBSERVABILITY`
  - `ENABLE_A365_OBSERVABILITY_EXPORTER`
  - `OTEL_SERVICE_NAME`
  - `OTEL_SERVICE_NAMESPACE`

---

## 6) Consolidar `.env` para despliegue

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab/infra/scripts
.\01-resource-group.ps1
.\02-foundry-maf.ps1
.\03-m365-service-principal.ps1
.\04-observability.ps1
```

Nota: cada script (`01` a `05`) invoca automáticamente `auth-permissions-helper.ps1` y detiene la ejecución si faltan permisos.

Copia manual obligatoria para que `05-webapp-m365.ps1` lea desde `.env`:

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
Copy-Item .\.env.generated .\.env -Force
```

PASS esperado:
- `.env.generated` y `.env` consolidados y sincronizados.
- `05-webapp-m365.ps1` tomará configuración desde `.env`.

---

## 7) Crear Web App (infra)

### 7.1 Crear/configurar App Service

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab/infra/scripts
.\05-webapp-m365.ps1
```

PASS esperado:
- Web App configurada correctamente.

---

## 8) Generar manifest + desplegar código (paso único)

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
.\dist\dev\build-m365-manifest.ps1
```

PASS esperado:
- `dist/m365-manifest/staging/manifest.json`
- `dist/m365-manifest/<project>-m365-manifest.zip`
- `dist/deploy/<project>-appservice-<timestamp>.zip`
- Deployment de código al App Service completado.

---

## 9) Pruebas en entorno cloud

### 9.1 Smoke HTTP

```powershell
$appCloud = "https://wapp-agent-identities-viewer.azurewebsites.net/api/messages"
$r = Invoke-WebRequest -Uri $appCloud -Method Get -SkipHttpErrorCheck
"HTTP_STATUS=$($r.StatusCode)"
```

PASS esperado: `401` o `405` (no `503`, no timeout).

### 9.2 Estado de deployment

```powershell
az webapp log deployment list --resource-group rg-agents-lab --name wapp-agent-identities-viewer --query "[0:5].{id:id,status:status,message:message,received:received_time}" -o table
```

### 9.3 Descargar logs de runtime

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

### 9.4 Playground contra cloud

```powershell
teamsapptester start -e https://wapp-agent-identities-viewer.azurewebsites.net/api/messages --channel-id msteams --delivery-mode expectReplies --cid $env:MICROSOFT_APP_ID --cs $env:MICROSOFT_APP_PASSWORD --tid $env:MICROSOFT_APP_TENANTID
```

PASS esperado:
- `/help`, `/clear` y mensaje libre responden correctamente en cloud.

---

## Checklist final (GO / NO-GO)

GO:
- CLI local PASS.
- Playground local PASS.
- Playground túnel PASS.
- Scripts `01`, `02`, `03`, `04`, `05` PASS.
- Manifest + ZIP generado en `dist/m365-manifest`.
- Deploy cloud PASS y endpoint estable.

NO-GO:
- `503` o timeout en cloud.
- Tracebacks recurrentes en logs de startup.
- Fallo en `/help` o mensaje normal en Playground (local/túnel/cloud).
