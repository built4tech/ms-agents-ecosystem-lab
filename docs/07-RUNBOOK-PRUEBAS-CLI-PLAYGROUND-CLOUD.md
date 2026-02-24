# Runbook de pruebas — CLI, Playground local y endpoint cloud

Runbook operativo para ejecutar y registrar el conjunto mínimo de pruebas funcionales y de regresión en tres superficies:

- CLI local (`main.py cli` / `main_cli.py`)
- Runtime local + Playground (`main_m365.py` + `teamsapptester`)
- Endpoint cloud (App Service)

---

## 1) Objetivo

Validar de forma repetible que:

1. El agente responde en CLI con identidad Entra (`AzureCliCredential`).
2. El runtime M365 local procesa actividades autenticadas desde Playground.
3. El endpoint cloud está accesible y protegido (sin degradarse a `503`/timeout).
4. El flujo end-to-end por canal funciona también contra el endpoint cloud.

---

## 2) Prerrequisitos

- `.env` en raíz con variables de Foundry y canal M365.
- `az login` activo en la suscripción correcta.
- Dependencias Python instaladas.
- `teamsapptester` instalado (`@microsoft/teams-app-test-tool`).
- Si usarás cloud:
  - URL del bot desplegado (ej. `https://<app>.azurewebsites.net/api/messages`).
  - Credenciales de app registration válidas para el canal.

Comprobaciones rápidas:

```powershell
az account show --output table
python --version
node --version
npm --version
```

---

## 3) Variables operativas recomendadas

```powershell
$repo = "c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab"
$appLocal = "http://127.0.0.1:3978/api/messages"
$appCloud = "https://wapp-agent-identities-viewer.azurewebsites.net/api/messages"
```

> Cambia `$appCloud` si el hostname objetivo cambia.

---

## 4) Matriz de pruebas

## A. CLI local

### A1. Smoke de arranque y salida

```powershell
Set-Location "$repo"
"exit" | python .\main.py cli
```

**PASS esperado**
- Inicializa sin excepción.
- Sale limpio con `exit`.

**Evidencia**
- Salida de consola (captura o transcript).

---

### A2. Prompt funcional básico

```powershell
Set-Location "$repo"
python .\main.py cli
```

En la sesión interactiva:
1. `hola`
2. pregunta de negocio corta
3. `clear`
4. `exit`

**PASS esperado**
- Responde en cada turno.
- `clear` reinicia contexto sin crash.

**Evidencia**
- Log/consola con los 4 turnos.

---

## B. Runtime local + Playground

### B1. Arranque runtime M365 local

Terminal 1:

```powershell
Set-Location "$repo"
python .\main_m365.py
```

**PASS esperado**
- Proceso queda escuchando en puerto local (`3978` por defecto).
- Sin traceback al iniciar.

---

### B2. Verificación de endpoint protegido (sin token)

Terminal 2:

```powershell
$r = Invoke-WebRequest -Uri $appLocal -Method Get -SkipHttpErrorCheck
"HTTP_STATUS=$($r.StatusCode)"
```

**PASS esperado (Fase 3)**
- `HTTP_STATUS=401` o respuesta de no autorizado equivalente.

**Nota**
- `401` aquí es correcto: valida enforcement de autenticación.

---

### B3. Playground local autenticado

Terminal 3 (cargar variables desde `.env`):

```powershell
Set-Location $repo
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
  if ($_ -match '^\s*([^=]+)=(.*)$') {
    [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
  }
}
```

Arranque Playground:

```powershell
teamsapptester start -e $appLocal --channel-id msteams --delivery-mode expectReplies --cid $env:MICROSOFT_APP_ID --cs $env:MICROSOFT_APP_PASSWORD --tid $env:MICROSOFT_APP_TENANTID
```

Casos a ejecutar en Playground:
1. `membersAdded` (bienvenida)
2. `/help`
3. `/clear`
4. Mensaje libre

**PASS esperado**
- 4/4 casos responden sin error no controlado.

**Evidencia**
- Captura de Playground + logs runtime.

---

## C. Endpoint cloud (App Service)

### C1. Smoke HTTP del endpoint público

```powershell
$r = Invoke-WebRequest -Uri $appCloud -Method Get -SkipHttpErrorCheck
"HTTP_STATUS=$($r.StatusCode)"
```

**PASS esperado**
- `401` (protegido) o `405` si solo acepta POST según configuración.
- **No** debe devolver `503` ni timeout.

---

### C2. Validación de deployment reciente

```powershell
az webapp log deployment list --resource-group rg-agents-lab --name wapp-agent-identities-viewer --query "[0:5].{id:id,status:status,message:message,received:received_time}" -o table
```

**PASS esperado**
- Último despliegue en estado exitoso (sin rollback por error runtime).

---

### C3. Descarga de logs para diagnóstico rápido

```powershell
$out = "$repo/dist/dev/wapp-logs-runbook.zip"
if (Test-Path $out) { Remove-Item $out -Force }
az webapp log download --resource-group rg-agents-lab --name wapp-agent-identities-viewer --log-file $out
```

**PASS esperado**
- ZIP generado.
- Sin `Traceback` crítico en arranque actual.

Búsqueda rápida:

```powershell
$dest = "$repo/dist/dev/wapp-logs-runbook"
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Expand-Archive -Path $out -DestinationPath $dest
Get-ChildItem "$dest/LogFiles/*_default_docker.log" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 |
  ForEach-Object { Select-String -Path $_.FullName -Pattern 'Traceback|ERROR|Exception|Running on|Listening' | Select-Object -Last 120 }
```

---

### C4. E2E por canal contra cloud (Playground)

```powershell
teamsapptester start -e $appCloud --channel-id msteams --delivery-mode expectReplies --cid $env:MICROSOFT_APP_ID --cs $env:MICROSOFT_APP_PASSWORD --tid $env:MICROSOFT_APP_TENANTID
```

Ejecutar mismos 4 casos de B3:
- bienvenida
- `/help`
- `/clear`
- mensaje libre

**PASS esperado**
- Respuesta funcional en cloud sin `401` (porque Playground va autenticado).

---

## D. Casos negativos obligatorios

### D1. Playground sin credenciales

Ejecutar `teamsapptester start` sin `--cid/--cs/--tid`.

**PASS esperado**
- Rechazo de autorización (`401`) y diagnóstico claro.

### D2. Runtime no disponible

Detener runtime local y repetir B2/B3.

**PASS esperado**
- Error de conexión explícito (sin ambigüedad), útil para troubleshooting.

---

## 5) Plantilla de resultados

| ID | Superficie | Caso | Resultado | Evidencia | Observaciones |
| --- | --- | --- | --- | --- | --- |
| A1 | CLI | Arranque + exit | PASS/FAIL | Consola | |
| A2 | CLI | Turnos + clear | PASS/FAIL | Consola | |
| B1 | Local runtime | Startup | PASS/FAIL | Log consola | |
| B2 | Local runtime | GET sin token | PASS/FAIL | HTTP status | |
| B3 | Playground local | 4 casos | PASS/FAIL | Captura/log | |
| C1 | Cloud | Smoke HTTP | PASS/FAIL | HTTP status | |
| C2 | Cloud | Deployment status | PASS/FAIL | Tabla az | |
| C3 | Cloud | Logs startup | PASS/FAIL | Extracto logs | |
| C4 | Cloud | Playground E2E | PASS/FAIL | Captura/log | |
| D1 | Negativo | Sin credenciales | PASS/FAIL | Error esperado | |
| D2 | Negativo | Runtime caído | PASS/FAIL | Error esperado | |

---

## 6) Criterio de aprobación

**GO**
- Todos los casos A, B y C en PASS.
- Casos negativos D con errores esperados y trazables.
- Sin `503`/timeout en endpoint cloud durante ventana de pruebas.

**NO-GO**
- Falla `/help` o mensaje normal en Playground (local o cloud).
- Arranque inestable con tracebacks recurrentes.
- Endpoint cloud vuelve a estado no operativo (`503` o timeout).

---

## 7) Frecuencia sugerida

- Antes de cada despliegue a cloud: A1, B1, B2.
- Después de cada despliegue: C1, C2, C3, C4.
- Cierre de sprint/release: ejecución completa de A+B+C+D.
