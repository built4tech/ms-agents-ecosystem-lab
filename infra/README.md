# Infraestructura - MS Agents Ecosystem Lab

Scripts de PowerShell para desplegar y gestionar el proyecto **Foundry (AIServices) para MAF**.

## Arquitectura

```
Resource Group: rg-agents-lab
└── Foundry (AIServices): foundry-maf-lab
    ├── Proyecto de agentes: foundry-maf-lab-project
    └── Deployment: gpt-4o-mini

Recursos asociados al recurso Foundry: cuenta AIServices y su proyecto de agentes.
```

## Requisitos previos
- Azure CLI instalado (no requiere extensión ML, necesaria para Azure OpenAI Hubs pero no para proyectos de Foundry)
- Permisos de Contributor en la subscription
- Cuota disponible para `gpt-4o-mini` en `eastus2`

## Autenticación
```powershell
az login
az account set --subscription "<subscription-id>"   # opcional
az account show
```

## Scripts disponibles
| Script | Descripción |
|--------|-------------|
| `00-auth.ps1` | Verifica autenticación y subscription activa |
| `01-resource-group.ps1` | Crea el Resource Group compartido |
| `02-foundry-maf.ps1` | Crea la cuenta Foundry, proyecto y deployment para MAF |
| `03-m365-service-principal.ps1` | Crea App Registration + Service Principal multitenant y actualiza `MICROSOFT_APP_*` en `.env.generated` |
| `04-observability.ps1` | Crea Log Analytics + Application Insights y actualiza variables OTel/App Insights en `.env.generated` |
| `05-webapp-m365.ps1` | Crea App Service (plan + web app) para el runtime M365 en región configurable y carga App Settings desde `.env.generated` |
| `deploy-all.ps1` | Ejecuta autenticación, RG y Foundry MAF en orden |
| `destroy-all.ps1` | Elimina el RG y purga soft-delete de la Foundry |
| `show-endpoints.ps1` | Script informativo (sin generación de `.env.generated`) |

## Uso rápido
```powershell
cd infra/scripts
.\deploy-all.ps1       # despliegue
.\03-m365-service-principal.ps1   # MICROSOFT_APP_*
.\04-observability.ps1            # APPLICATIONINSIGHTS_* y OTel
.\05-webapp-m365.ps1              # App Service para canal M365
.\destroy-all.ps1      # limpieza
```

## Orden recomendado para Fase M365

```powershell
cd infra/scripts
.\deploy-all.ps1
.\03-m365-service-principal.ps1
.\04-observability.ps1
.\05-webapp-m365.ps1
```

Flujo operativo recomendado:
1. `01-resource-group.ps1` crea/actualiza la sección Azure en `.env.generated`.
2. `02-foundry-maf.ps1` complementa la sección Foundry en `.env.generated`.
3. `03-m365-service-principal.ps1` complementa la sección M365 en `.env.generated`.
4. `04-observability.ps1` complementa la sección observabilidad en `.env.generated`.
5. Copia manualmente `.env.generated` a `.env` para pruebas locales.
6. Ejecuta `05-webapp-m365.ps1`, que carga los valores de `.env.generated` como App Settings de la Web App.

Con esto, en cloud la aplicación no depende de archivo `.env`.

## Configuración
Archivo: `infra/config/lab-config.ps1`
```powershell
$script:Location = "eastus2"
$script:ResourceGroupName = "rg-agents-lab"
$script:FoundryName = "foundry-maf-lab"
$script:ModelName = "gpt-4o-mini"
$script:ModelVersion = "2024-07-18"
$script:ModelSku = "GlobalStandard"
$script:ModelCapacity = 10
```

Variables opcionales adicionales (si no se definen, los scripts usan defaults):

```powershell
# 03 - App registration M365
$script:M365AppDisplayName = "agent-identities-viewer-m365"

# 04 - Observabilidad
$script:LogAnalyticsWorkspaceName = "law-agents-lab"
$script:ApplicationInsightsName = "appi-agents-lab"

# 05 - App Service runtime M365
$script:WebAppLocation = "spaincentral"          # puede ser distinta a Location
$script:WebAppName = "wapp-agent-identities-viewer"
$script:AppServicePlanName = "asp-agent-identities-viewer"
$script:AppServicePlanSku = "B1"

# OTel fijo
$script:OtelServiceName = "agent_viewer"
$script:OtelServiceNamespace = "agent_viewer_Name_Space"
```

## Variables de entorno
El archivo `.env.generated` se mantiene por secciones, una por script (`01..04`) con cabecera:

`Fichero: <script> | Fecha: dd-MM-yy HH:mm`

Tras ejecutar `01-resource-group.ps1` y `02-foundry-maf.ps1` obtendrás:
- `ENDPOINT_API`
- `ENDPOINT_OPENAI`
- `DEPLOYMENT_NAME`
- `PROJECT_NAME`
- `API_VERSION`

Adicionalmente:
- `MICROSOFT_APP_ID`
- `MICROSOFT_APP_PASSWORD`
- `MICROSOFT_APP_TYPE`
- `MICROSOFT_APP_TENANTID`
- `APPLICATIONINSIGHTS_CONNECTION_STRING`
- `ENABLE_OBSERVABILITY=true`
- `ENABLE_A365_OBSERVABILITY_EXPORTER=false`
- `OTEL_SERVICE_NAME` (desde `lab-config.ps1`, valor por defecto `agent_viewer`)
- `OTEL_SERVICE_NAMESPACE` (desde `lab-config.ps1`, valor por defecto `agent_viewer_Name_Space`)

Nota de idempotencia en observabilidad (`04-observability.ps1`):
- La región objetivo de observabilidad es `Location` (misma base del lab).
- Si `law-agents-lab` o `appi-agents-lab` existen en otra región, el script crea nombres alternativos en la región objetivo (en lugar de reutilizar fuera de región).
- Excepción intencional de región: solo la Web App puede ir en `WebAppLocation` (por ejemplo `spaincentral`) según necesidad de licenciamiento.

## Costes y buenas prácticas
- Ejecuta `destroy-all.ps1` cuando no uses el entorno para evitar costes.
- Eliminar el RG purga todos los recursos creados.

## Troubleshooting
- `CannotDeleteResource`: espera a que terminen dependencias o usa el flujo de purga incluido.
- `Quota exceeded`: solicita aumento de cuota o cambia de región en `lab-config.ps1`.
