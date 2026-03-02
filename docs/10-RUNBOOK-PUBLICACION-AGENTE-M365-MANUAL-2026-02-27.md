# 10 - RUNBOOK PUBLICACIÓN AGENTE M365 (MANUAL) - 2026-02-27

## 1) Objetivo y alcance
Este runbook documenta el flujo **que sí ha funcionado** para publicar el agente en Microsoft 365/Teams, priorizando estabilidad y repetibilidad.

Resultado final esperado:
- Generar un `manifest.zip` válido.
- Publicar el paquete manualmente en Teams/M365 Admin Center.
- Mantener runtime local sin romper pruebas (`AGENT_HOST=localhost`).

> Nota: El flujo `a365 publish` quedó bloqueado por autorización contra Titles (401/403) aunque la publicación manual del paquete sí funcionó.

---

## 2) Arquitectura operativa (lo que funcionó)
### 2.1 Dos identidades separadas (válido)
1. **Runtime/Bot App (Web App)**
   - Usa variables en `.env`:
     - `MICROSOFT_APP_ID`
     - `MICROSOFT_APP_PASSWORD`
   - Esta identidad es la que atiende `/api/messages`.
2. **Blueprint Agent 365 (control plane)**
   - Se crea con `a365 setup blueprint`.
   - Se guarda en `dist/a365/a365.generated.config.json`.

Este modelo **separado** es válido y fue el más estable para completar publicación manual.

### 2.2 Estructura de artefactos consolidada
Se estandarizó `dist/deploy` así:
- `dist/deploy/m365/manifest/`
  - `manifest.json`
  - `agenticUserTemplateManifest.json`
  - `color.png`
  - `outline.png`
- `dist/deploy/m365/package/`
  - `manifest.zip` (único zip de publicación)
- `dist/deploy/webapp/staging/`
- `dist/deploy/webapp/package/`
  - `webapp.zip` (único zip de runtime)

---

## 3) Prerrequisitos
## 3.1 Herramientas
- `az` (Azure CLI) autenticado en tenant correcto.
- `a365` instalado y funcional.
- PowerShell disponible.

## 3.2 Cuenta
- Cuenta con permisos de administración suficientes en tenant para setup/consent.

## 3.3 Configuración base en `.env`
Valores clave (sin exponer secretos en este documento):
- `MICROSOFT_APP_ID=<app-id-runtime-bot>`
- `MICROSOFT_APP_PASSWORD=<secret-runtime-bot>`
- `MICROSOFT_APP_TENANTID=<tenant-id>`
- `WEB_APP_NAME=<nombre-webapp>`
- `AGENT_HOST=localhost`
- `AGENT_VALID_DOMAIN=<host-publico-webapp>`

**Importante**
- `AGENT_HOST` se usa para bind local del servidor.
- `AGENT_VALID_DOMAIN` se usa para `validDomains` del manifest cloud.

---

## 4) Flujo end-to-end (paso a paso)
## 4.1 Limpieza previa de estado A365 (recomendado al reiniciar)
Desde raíz del repo:

```powershell
Remove-Item .\dist\a365 -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path .\dist\a365 | Out-Null
```

Comprobar que no hay estados anteriores:
- `dist/a365/a365.config.json` (se recreará)
- `dist/a365/a365.generated.config.json` (se recreará)

## 4.2 Inicializar A365
```powershell
Set-Location .\dist\a365
a365 config init
```

Durante el asistente:
- `Deployment project path` para detección de plataforma: usar ruta con runtime Python (por ejemplo `..\deploy\webapp\staging` o raíz del proyecto).

Después de `init`, ajustar `deploymentProjectPath` en `dist/a365/a365.config.json` a:
- `C:\Users\<usuario>\...\dist\deploy\m365`

(Es el path correcto para que A365 localice manifest para publish/manual packaging.)

## 4.3 Crear blueprint mínimo (sin deployment)
```powershell
Set-Location .\dist\a365
a365 setup blueprint -v
```

Resultado esperado:
- `agentBlueprintId` en `dist/a365/a365.generated.config.json`.
- `resourceConsents` con estado positivo.

Validación:
```powershell
a365 config display -a
```

## 4.4 Generar manifest y package
```powershell
Set-Location ..\dev
.\build-m365-manifest.ps1 -SkipWebAppDeploy
```

Resultados esperados:
- `dist/deploy/m365/manifest/manifest.json`
- `dist/deploy/m365/manifest/agenticUserTemplateManifest.json`
- `dist/deploy/m365/package/manifest.zip`

## 4.5 Validar manifest antes de subir
### 4.5.1 Scopes de bot válidos
Debe incluir solo:
- `personal`
- `team`

No incluir `groupchat` en este entorno, porque generó error de validación en upload:
- `bots[0].scopes[2] is invalid`
- `bots[0].commandLists[0].scopes[2] is invalid`

### 4.5.2 Dominio válido
`validDomains` debe contener host público de la web app (no `localhost`) para publicación cloud.

## 4.6 Publicación manual (flujo exitoso)
Subir en Teams/M365 Admin Center:
- Archivo: `dist/deploy/m365/package/manifest.zip`

Este flujo manual fue el que completó la publicación correctamente.

---

## 5) Comandos de comprobación rápida
## 5.1 Identidad Azure activa
```powershell
az account show --query "{tenant:tenantId,user:user.name}" -o table
```

## 5.2 Estado A365 fusionado
```powershell
Set-Location .\dist\a365
a365 config display -a
```

## 5.3 Regenerar package de publicación
```powershell
Set-Location ..\dev
.\build-m365-manifest.ps1 -SkipWebAppDeploy
```

## 5.4 Verificar scopes en manifest
```powershell
$manifest = Get-Content .\dist\deploy\m365\manifest\manifest.json -Raw | ConvertFrom-Json
$manifest.bots[0].scopes
$manifest.bots[0].commandLists[0].scopes
```

---

## 6) Diferencia clave: publish CLI vs manual
## 6.1 Manual (funcionó)
- Upload directo de `manifest.zip` en Admin Center.
- Permitió completar publicación del agente.

## 6.2 `a365 publish` (no bloqueante para este runbook, pero falló)
- Llegó a actualizar manifest y crear zip correctamente.
- Falló en endpoint Titles (`titles.prod.mos.microsoft.com`) con 401/403 en la fase final de upload.

Conclusión operativa:
- Mantener publicación manual hasta resolver autorizaciones de Titles/MOS con Microsoft.

---

## 7) Checklist operativo final
Antes de publicar:
- [ ] `a365 setup blueprint -v` completado.
- [ ] `a365 config display -a` muestra `agentBlueprintId`.
- [ ] `build-m365-manifest.ps1 -SkipWebAppDeploy` ejecutado sin errores.
- [ ] `manifest.json` con scopes `personal, team` (sin `groupchat`).
- [ ] `validDomains` con host cloud.
- [ ] Existe `dist/deploy/m365/package/manifest.zip`.

Después de publicar:
- [ ] App visible en catálogo de apps.
- [ ] Instalación en ámbito personal correcta.
- [ ] Bot responde en `personal` y `team`.

---

## 8) Referencias de archivos clave
- Config A365: `dist/a365/a365.config.json`
- Estado generado A365: `dist/a365/a365.generated.config.json`
- Template manifest: `dist/dev/manifest.template.json`
- Script generación: `dist/dev/build-m365-manifest.ps1`
- Manifest final: `dist/deploy/m365/manifest/manifest.json`
- ZIP publicación manual: `dist/deploy/m365/package/manifest.zip`

---

## 9) Lecciones aprendidas (solo prácticas efectivas)
1. Separar `AGENT_HOST` (runtime local) de `AGENT_VALID_DOMAIN` (manifest cloud) evita romper pruebas locales.
2. Mantener un único `manifest.zip` evita confusión al publicar.
3. Validar scopes antes de subir evita errores de schema en portal.
4. Publicación manual puede ser ruta estable incluso si `a365 publish` falla en Titles.
5. Mantener runbook y estructura fija reduce errores de repetición.
