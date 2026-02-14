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
| `deploy-all.ps1` | Ejecuta autenticación, RG y Foundry MAF en orden |
| `destroy-all.ps1` | Elimina el RG y purga soft-delete de la Foundry |
| `show-endpoints.ps1` | Muestra endpoints y genera `.env.generated` para MAF |

## Uso rápido
```powershell
cd infra/scripts
.\deploy-all.ps1       # despliegue
.\show-endpoints.ps1   # variables y .env.generated
.\destroy-all.ps1      # limpieza
```

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

## Variables de entorno
Ejecuta `show-endpoints.ps1` para obtener `.env.generated` con:
- `MAF_ENDPOINT_API`
- `MAF_ENDPOINT_OPENAI`
- `MAF_DEPLOYMENT_NAME`
- `MAF_PROJECT_NAME`
- `MAF_API_VERSION`

## Costes y buenas prácticas
- Ejecuta `destroy-all.ps1` cuando no uses el entorno para evitar costes.
- Eliminar el RG purga todos los recursos creados.

## Troubleshooting
- `CannotDeleteResource`: espera a que terminen dependencias o usa el flujo de purga incluido.
- `Quota exceeded`: solicita aumento de cuota o cambia de región en `lab-config.ps1`.
