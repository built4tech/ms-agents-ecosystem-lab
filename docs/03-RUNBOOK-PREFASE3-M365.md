# Runbook pre-Fase 3 (M365)

Documento operativo corto para ejecutar validaciones **Go/No-Go** antes de iniciar Fase 3 (integración/publicación en canal real).

## Alcance

Este runbook valida:

- Funcionamiento CLI (`main.py cli` / `main_cli.py`)
- Funcionamiento endpoint runtime M365 (`main_m365.py`)
- Validación manual por `POST /api/messages`
- Validación con Microsoft 365 Agents Playground
- Diagnóstico mínimo de errores frecuentes

No cubre publicación productiva ni configuración final de canal Copilot/Teams (eso pertenece a Fase 3).

---

## Prerrequisitos

## 1) Dependencias

Desde raíz del repositorio:

```powershell
python --version
node --version
npm --version
```

Instala dependencias necesarias:

```powershell
pip install -r requirements.txt
npm install -g @microsoft/teams-app-test-tool
```

## 2) Entorno y autenticación

- `.env` configurado en raíz (`/.env`)
- Sesión Azure activa:

```powershell
az login
az account show --output table
```

---

## Ejecución de pruebas

## 3) Smoke test CLI

En terminal A:

```powershell
cd .
python .\main.py cli
```

Prueba rápida:

1. Pregunta simple (ej. `Hola`)
2. `exit`

**Criterio OK**: responde y cierra sin errores.

---

## 4) Arranque endpoint runtime M365

En terminal A:

```powershell
cd .
python .\main_m365.py
```

Si falla con puerto ocupado (`Errno 10048`): cerrar proceso previo o cambiar `PORT` en `.env`.

---

## 5) Health-check endpoint

En terminal B:

```powershell
Invoke-RestMethod -Uri "http://localhost:3978/api/messages" -Method Get
```

**Criterio OK**: estado `200`.

---

## 6) POST funcional manual (expectReplies)

En terminal B:

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

**Criterio OK**:

- Respuesta con `activities`
- Al menos una actividad `message` con texto del agente

---

## 7) Validación con Playground

En terminal C:

```powershell
teamsapptester
```

Configurar endpoint del agente:

- `http://127.0.0.1:3978/api/messages`

Casos mínimos:

1. Alta conversación (`membersAdded`) -> bienvenida
2. `/help` -> ayuda
3. `/clear` -> limpieza
4. Mensaje normal -> respuesta de Foundry

**Criterio OK**: los 4 casos pasan y no hay excepciones no controladas en logs.

---

## Casos negativos obligatorios

## 8) Payload inválido

Enviar body incompleto (sin `type`) y verificar error trazable.

**Criterio OK**: error controlado en logs y diagnóstico claro.

## 9) Token inválido/expirado

Simular sesión sin contexto válido de Azure CLI.

**Criterio OK**: error explícito de credencial/tóken, sin bloqueo de proceso.

---

## Registro de resultados (plantilla)

Usa esta tabla para dejar trazabilidad:

| Caso | Resultado | Evidencia | Observaciones |
| --- | --- | --- | --- |
| CLI smoke test | PASS/FAIL | consola | |
| GET /api/messages | PASS/FAIL | status code | |
| POST expectReplies | PASS/FAIL | response json | |
| Playground membersAdded | PASS/FAIL | screenshot/log | |
| Playground /help | PASS/FAIL | screenshot/log | |
| Playground /clear | PASS/FAIL | screenshot/log | |
| Playground mensaje normal | PASS/FAIL | screenshot/log | |
| Payload inválido | PASS/FAIL | log error | |
| Token inválido | PASS/FAIL | log error | |

---

## Criterio Go/No-Go final

**GO Fase 3** si:

- Todos los casos funcionales PASS
- Casos negativos con errores esperados y trazables
- Sin errores críticos no controlados en servidor
- Consistencia entre prueba manual y Playground

**NO-GO Fase 3** si:

- Fallan `/help` o mensaje normal
- Inestabilidad en arranque endpoint
- Errores de identidad no diagnosticados
