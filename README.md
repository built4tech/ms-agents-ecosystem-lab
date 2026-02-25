
# ms-agents-ecosystem-lab

Laboratorio centrado en **Microsoft Agent Framework (MAF)** sobre Azure AI Foundry.

## Documentación clave (M365 runtime)

Para seguir la evolución del agente hacia Microsoft 365/Copilot, utiliza esta secuencia:

1. Plan por fases y decisiones: [docs/01-PLAN-M365-AGENT365.md](docs/01-PLAN-M365-AGENT365.md)
    - Define el roadmap incremental, criterios por fase y decisiones de arquitectura/autenticación.
2. Guía de flujo técnico runtime: [docs/02-GUIA-FLUJO-RUNTIME-M365.md](docs/02-GUIA-FLUJO-RUNTIME-M365.md)
    - Explica en detalle cómo funciona `main_m365.py`, el endpoint `/api/messages`, estructura de Activity y handlers.
3. Runbook operativo unificado: [docs/09-RUNBOOK-UNIFICADO-M365.md](docs/09-RUNBOOK-UNIFICADO-M365.md)
    - Runbook maestro con validaciones CLI + local + túnel + infra + cloud en un solo documento.

Runbooks históricos conservados para revisión:
- [docs/03-RUNBOOK-PREFASE3-M365.md](docs/03-RUNBOOK-PREFASE3-M365.md)
- [docs/04-RUNBOOK-FASE3-LOCAL-TUNEL-M365.md](docs/04-RUNBOOK-FASE3-LOCAL-TUNEL-M365.md)
- [docs/07-RUNBOOK-PRUEBAS-CLI-PLAYGROUND-CLOUD.md](docs/07-RUNBOOK-PRUEBAS-CLI-PLAYGROUND-CLOUD.md)
- [docs/08-RUNBOOK-E2E-CLI-INFRA-PLAYGROUND-CLOUD.md](docs/08-RUNBOOK-E2E-CLI-INFRA-PLAYGROUND-CLOUD.md)

## Objetivos
1. Probar rápidamente un entorno MAF completo en Azure AI Foundry.
2. Ejecutar ejemplos incrementales (simple chat y extensiones de canal M365) sobre un único recurso de Azure AI Foundry.
3. Mantener scripts de infraestructura mínimos y reproducibles.

## Estado de alcance (2026-02-24)

- El alcance activo del laboratorio se centra en un único runtime de agente en la **raíz del repositorio**.
- La estructura histórica por plataformas quedó retirada para evitar duplicidad de código y rutas.
- La documentación y los runbooks actuales deben interpretarse con esta estructura raíz.

## Estructura del proyecto

```
ms-agents-ecosystem-lab/
├── app/
├── tests/
├── main.py
├── main_cli.py
├── main_m365.py
├── infra/
│   ├── config/
│   │   └── lab-config.ps1
│   └── scripts/
│       ├── auth-permissions-helper.ps1
│       ├── 01-resource-group.ps1
│       ├── 02-foundry-maf.ps1
│       ├── deploy-all.ps1
│       ├── destroy-all.ps1
│       └── show-endpoints.ps1
├── docs/
│   ├── azure-cli-auth.md
│   ├── 01-PLAN-M365-AGENT365.md
│   ├── 02-GUIA-FLUJO-RUNTIME-M365.md
│   └── 03-RUNBOOK-PREFASE3-M365.md
├── dist/
│   ├── dev/
│   │   ├── build-m365-manifest.ps1
│   │   └── manifest.template.json
│   ├── deploy/
│   └── m365-manifest/
├── requirements.txt
├── .env.example
└── README.md
```

## Cómo empezar

### 1. Requisitos previos
- Azure CLI instalada (no requiere extensión ML)
- Python 3.10+
- Permisos RBAC para crear recursos (Contributor u Owner)
- Permiso para asignación de roles cuando aplique (`Owner`, `User Access Administrator` o `Role Based Access Control Administrator`)

### 1.1 Requisito opcional (altamente recomendado): Node.js + npm

Es altamente recomendable instalar `npm` para poder usar **Microsoft 365 Agents Playground** en pruebas locales del endpoint `/api/messages`.

Instalación sugerida en Windows:

```powershell
winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
```

Luego abre una terminal nueva y verifica:

```powershell
node --version
npm --version
```

### 1.2 Requisito opcional (altamente recomendado): Playground local

Instala Microsoft 365 Agents Playground:

```powershell
npm install -g @microsoft/teams-app-test-tool
```

Invocación de la herramienta:

```powershell
teamsapptester
```

Uso recomendado:

- Arranca el servidor del agente (`main_m365.py`).
- Conecta Playground contra `http://127.0.0.1:3978/api/messages`.
- Ejecuta casos `/help`, `/clear`, mensaje normal y casos negativos.
- Referencia operativa completa: [docs/09-RUNBOOK-UNIFICADO-M365.md](docs/09-RUNBOOK-UNIFICADO-M365.md)

### 2. Autenticación
```powershell
az login --tenant <tu-tenant>
az account show --query "{Usuario:user.name, Suscripcion:name}" --output table
```
Si manejas múltiples cuentas, revisa [docs/azure-cli-auth.md](docs/azure-cli-auth.md).

### 3. Configurar infraestructura
```powershell
cd infra/config
copy lab-config.example.ps1 lab-config.ps1
# Edita lab-config.ps1 si necesitas cambiar región o nombres
```

### 4. Desplegar infraestructura
```powershell
cd ..\scripts
.\deploy-all.ps1
```

### 5. Generar variables de entorno
```powershell
.\03-m365-service-principal.ps1
.\04-observability.ps1
copy ..\..\.env.generated ..\..\.env
```
Consulta [.env.example](.env.example) para conocer cada variable.

### 5.1 Flujo manual requerido para App Service M365

El script `05-webapp-m365.ps1` **no** forma parte de `deploy-all.ps1`.

Debe ejecutarse manualmente después de completar esta secuencia:

```powershell
cd ..\scripts
.\03-m365-service-principal.ps1
.\04-observability.ps1
copy ..\..\.env.generated ..\..\.env
.\05-webapp-m365.ps1
```

Razón: `05-webapp-m365.ps1` carga las App Settings de la Web App desde `.env.generated`, y ese archivo debe estar previamente completado por `01..04` y revisado.

### 6. Instalar dependencias
```powershell
cd ..\..
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### 7. Ejecutar un ejemplo
```powershell
cd .
python main.py cli
```

### 8. Ejecutar endpoint M365 (runtime)

```powershell
cd .
python main_m365.py
```

Endpoint local:

- `GET http://localhost:3978/api/messages` (health-check)
- `POST http://localhost:3978/api/messages` (Activity protocol)

## Arquitectura en Azure

```
Resource Group: rg-agents-lab
└── Azure AI Foundry (AIServices): foundry-maf-lab
    ├── Proyecto de agentes: foundry-maf-lab-project
    └── Deployment: gpt-4o-mini
```

## Limpieza
```powershell
cd infra/scripts
.\destroy-all.ps1
```
Confirma escribiendo `ELIMINAR` cuando se solicite para evitar costes innecesarios.

## Lectura recomendada para avanzar a Fase 3

1. [docs/01-PLAN-M365-AGENT365.md](docs/01-PLAN-M365-AGENT365.md)
2. [docs/02-GUIA-FLUJO-RUNTIME-M365.md](docs/02-GUIA-FLUJO-RUNTIME-M365.md)
3. [docs/09-RUNBOOK-UNIFICADO-M365.md](docs/09-RUNBOOK-UNIFICADO-M365.md)
