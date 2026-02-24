# Runbook Fase 3 — Validación local + túnel (M365)

Documento operativo adicional para validar Fase 3 sin perder capacidad de pruebas locales.

## Alcance

Este runbook cubre:

- Regresión local de CLI (`main.py`) con Entra ID (`AzureCliCredential`)
- Arranque local de runtime M365 (`main_m365.py`) con auth de canal (service principal)
- Verificación de enforcement de seguridad (`401` sin token)
- Prueba de canal mediante Microsoft 365 Agents Playground + túnel

No cubre despliegue productivo final ni observabilidad avanzada de fases posteriores.

---

## Prerrequisitos

- `.env` raíz con valores válidos:
  - `ENDPOINT_API`, `DEPLOYMENT_NAME`, `API_VERSION`
  - `MICROSOFT_APP_ID`, `MICROSOFT_APP_PASSWORD`, `MICROSOFT_APP_TENANTID`
- `az login` activo
- Dependencias instaladas (`requirements.txt` y `platforms/maf/01-simple-chat/requirements-m365.txt`)
- `teamsapptester` disponible
- Entorno virtual activo (`.venv`) o ejecución explícita con `./.venv/Scripts/python.exe`

---

## Secuencia mínima (6 comandos)

> Ejecuta en terminales separadas cuando se indique.

### 1) Confirmar identidad Azure (Terminal A)

```powershell
az account show --output table
```

**OK esperado:** cuenta y tenant correctos.

### 2) Regresión CLI local (Terminal A)

```powershell
cd platforms/maf/01-simple-chat
"exit" | C:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab/.venv/Scripts/python.exe .\main.py
```

**OK esperado:** inicializa agente y termina limpio.

### 3) Arrancar runtime M365 autenticado (Terminal B)

```powershell
cd platforms/maf/01-simple-chat
C:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab/.venv/Scripts/python.exe .\main_m365.py
```

**OK esperado:** `Running on http://localhost:3978`.

### 4) Verificar acceso directo no autenticado (Terminal C)

```powershell
try {
  Invoke-RestMethod -Uri "http://localhost:3978/api/messages" -Method Get -ErrorAction Stop
} catch {
  $_.Exception.Message
}
```

**OK esperado (Fase 3):** `401 Unauthorized`.

### 5) Abrir Playground local (Terminal D)

Antes de lanzar Playground, carga variables de `/.env` en la sesión de PowerShell actual:

```powershell
Set-Location c:/Users/carlosmu/Documents/code/ms-agents-ecosystem-lab
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
  if ($_ -match '^\s*([^=]+)=(.*)$') {
    [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
  }
}
```

Valida que las variables de canal quedaron cargadas:

```powershell
@('MICROSOFT_APP_ID','MICROSOFT_APP_PASSWORD','MICROSOFT_APP_TENANTID') | ForEach-Object {
  $name = $_
  $value = [Environment]::GetEnvironmentVariable($name, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) { "$name=MISSING" } else { "$name=SET" }
}
```

```powershell
teamsapptester start -e http://127.0.0.1:3978/api/messages --channel-id msteams --delivery-mode expectReplies --cid $env:MICROSOFT_APP_ID --cs $env:MICROSOFT_APP_PASSWORD --tid $env:MICROSOFT_APP_TENANTID
```

**OK esperado:** Playground abre y conecta contra el endpoint del agente sin `401`.

Nota: en Fase 3, el endpoint exige autenticación. Si inicias Playground sin `--cid/--cs/--tid`, verás `401 Authorization header not found`.

### 6) Exponer local con túnel para prueba de canal

Ejemplo con Dev Tunnels (si está habilitado en tu entorno):

```powershell
devtunnel user login --entra --use-browser-auth
```

Luego crea/hostea el túnel:

```powershell
devtunnel host -p 3978 --allow-anonymous
```

Si PowerShell indica `devtunnel` no reconocido:

```powershell
winget install --id Microsoft.devtunnel -e --accept-package-agreements --accept-source-agreements
```

Luego abre una terminal nueva y reintenta `devtunnel host -p 3978 --allow-anonymous`.

Fallback inmediato sin reiniciar terminal (ruta instalada por winget):

```powershell
C:/Users/carlosmu/AppData/Local/Microsoft/WinGet/Packages/Microsoft.devtunnel_Microsoft.Winget.Source_8wekyb3d8bbwe/devtunnel.exe host -p 3978 --allow-anonymous
```

Si aparece el error `Unauthorized tunnel creation access: Anonymous does not have 'create' access scope`, significa que falta autenticación de usuario en el CLI. Ejecuta primero `devtunnel user login --entra --use-browser-auth` y vuelve a correr `host`.

Configura en Playground/Bot endpoint público resultante (`https://<tu-subdominio>/api/messages`).

Si quieres iniciar Playground ya apuntando al túnel:

```powershell
teamsapptester start -e https://<tu-subdominio>/api/messages --channel-id msteams --delivery-mode expectReplies --cid $env:MICROSOFT_APP_ID --cs $env:MICROSOFT_APP_PASSWORD --tid $env:MICROSOFT_APP_TENANTID
```

**OK esperado:** mensajes `/help` y mensaje normal responden end-to-end.

---

## Criterios PASS/FAIL

| Caso | Resultado esperado |
| --- | --- |
| CLI (`main.py`) | PASS |
| Runtime M365 (`main_m365.py`) | PASS |
| GET directo sin token | `401` (PASS) |
| Playground conectado por túnel | PASS |
| `/help` en canal | PASS |
| Mensaje normal en canal | PASS |

---

## Notas de continuidad

- Este comportamiento es intencional en Fase 3: el canal requiere autenticación; la prueba directa anónima deja de ser válida.
- La autenticación local de Foundry para CLI se mantiene por `AzureCliCredential` y no se reemplaza por API key.
