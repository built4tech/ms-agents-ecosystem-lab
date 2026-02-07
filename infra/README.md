# Infraestructura - MS Agents Ecosystem Lab

Scripts de PowerShell para desplegar y gestionar la infraestructura en Azure.

## Arquitectura

```
Resource Group: rg-agents-lab
└── AI Foundry Hub: hub-agents-lab
    ├── project-foundry-agents/    → Foundry SDK experiments
    │   └── gpt-4o-mini deployment
    ├── project-maf-agents/        → Microsoft Agent Framework experiments
    │   └── gpt-4o-mini deployment
    └── project-crewai-agents/     → CrewAI experiments
        └── gpt-4o-mini deployment

Recursos compartidos (creados con el Hub):
├── Storage Account
├── Key Vault
├── Application Insights
└── Log Analytics Workspace
```

## Requisitos previos

1. **Azure CLI** instalado ([guía de instalación](https://docs.microsoft.com/cli/azure/install-azure-cli))
2. **Extensión ML** de Azure CLI:
   ```powershell
   az extension add --name ml
   ```
3. **Subscription de Azure** con permisos de Contributor
4. **Cuota disponible** para gpt-4o-mini en la región eastus2
5. **Archivo de configuración**: Copia el archivo de ejemplo y configura tu subscription:
   ```powershell
   cd infra/config
   copy lab-config.example.ps1 lab-config.ps1
   # Edita lab-config.ps1 y actualiza $script:SubscriptionId si es necesario
   ```

## Autenticación

```powershell
# Login interactivo
az login

# Seleccionar subscription (si tienes varias)
az account set --subscription "<subscription-id>"

# Verificar
az account show
```

## Scripts disponibles

| Script | Descripción |
|--------|-------------|
| `00-auth.ps1` | Verifica autenticación y muestra subscription activa |
| `01-resource-group.ps1` | Crea el Resource Group compartido |
| `02-ai-hub.ps1` | Crea el AI Foundry Hub y recursos dependientes |
| `03-project-foundry.ps1` | Crea proyecto y deployment para Foundry SDK |
| `04-project-maf.ps1` | Crea proyecto y deployment para MAF |
| `05-project-crewai.ps1` | Crea proyecto y deployment para CrewAI |
| `deploy-all.ps1` | **Ejecuta todos los scripts en orden** |
| `destroy-all.ps1` | Elimina todo el Resource Group |
| `show-endpoints.ps1` | Muestra endpoints y genera `.env.generated` |

## Uso rápido

### Desplegar toda la infraestructura

```powershell
cd infra/scripts
.\deploy-all.ps1
```

Tiempo estimado: 10-15 minutos

### Ver endpoints y variables de entorno

```powershell
.\show-endpoints.ps1
```

Esto genera un archivo `.env.generated` con todas las variables necesarias.

### Destruir infraestructura

```powershell
.\destroy-all.ps1
```

⚠️ **Requiere confirmación**: Debes escribir `ELIMINAR` para proceder.

## Despliegue individual

Si prefieres desplegar componentes específicos:

```powershell
# Solo autenticación
.\00-auth.ps1

# Solo Resource Group
.\01-resource-group.ps1

# Solo Hub (requiere RG)
.\02-ai-hub.ps1

# Solo proyecto específico (requiere Hub)
.\03-project-foundry.ps1
.\04-project-maf.ps1
.\05-project-crewai.ps1
```

## Configuración

Las variables de configuración están en `config/lab-config.ps1`:

```powershell
# Región
$script:Location = "eastus2"

# Nombres de recursos
$script:ResourceGroupName = "rg-agents-lab"
$script:HubName = "hub-agents-lab"

# Proyectos
$script:Projects = @{
    Foundry = "project-foundry-agents"
    MAF     = "project-maf-agents"
    CrewAI  = "project-crewai-agents"
}

# Modelo
$script:ModelName = "gpt-4o-mini"
```

Modifica este archivo si necesitas cambiar nombres o región.

## Variables de entorno y conexión

Después del despliegue, ejecuta `.\show-endpoints.ps1` para obtener las variables de conexión.

### Patrón de conexión unificado

Todos los frameworks usan `DefaultAzureCredential` para autenticación y variables de entorno similares:

| Variable | Descripción |
|----------|-------------|
| `*_ENDPOINT` | URL del servicio |
| `*_DEPLOYMENT_NAME` | Nombre del modelo desplegado |
| `*_PROJECT_NAME` | Nombre del proyecto (solo Foundry/MAF) |

### Foundry SDK (`platforms/foundry/`)

Usa endpoint de Azure AI Services. Los agentes aparecen en el portal de Foundry.

```python
import os
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

client = AIProjectClient(
    endpoint=os.getenv("FOUNDRY_ENDPOINT"),
    credential=DefaultAzureCredential()
)

# Crear agente (visible en Foundry Portal)
agent = client.agents.create_agent(
    model=os.getenv("FOUNDRY_DEPLOYMENT_NAME"),
    name="foundry-agent",
    instructions="Eres un asistente útil."
)
```

### Microsoft Agent Framework (`platforms/maf/`)

Usa endpoint de Azure AI Services. Los agentes aparecen en el portal de Foundry.

```python
import os
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

client = AIProjectClient(
    endpoint=os.getenv("MAF_ENDPOINT"),
    credential=DefaultAzureCredential()
)

# MAF usa el mismo Agent Service
agent = client.agents.create_agent(
    model=os.getenv("MAF_DEPLOYMENT_NAME"),
    name="maf-agent",
    instructions="Eres un asistente útil."
)
```

### CrewAI (`platforms/crewai/`)

Usa endpoint OpenAI-compatible con Azure Identity. Los agentes NO aparecen en el portal (son objetos en memoria).

```python
import os
from azure.identity import DefaultAzureCredential
from crewai import Agent, LLM

# Obtener token de Azure Identity
credential = DefaultAzureCredential()
token = credential.get_token("https://cognitiveservices.azure.com/.default").token

llm = LLM(
    model=f"azure/{os.getenv('CREWAI_DEPLOYMENT_NAME')}",
    api_key=token,  # Token de Azure Identity
    base_url=os.getenv("CREWAI_ENDPOINT")
)

# Agente CrewAI (solo en memoria)
agent = Agent(
    role="Investigador",
    goal="Investigar y analizar información",
    backstory="Eres un investigador experto.",
    llm=llm
)
```

### Resumen de diferencias

| Framework | Tipo de Endpoint | Auth | Agentes en Portal |
|-----------|------------------|------|-------------------|
| Foundry SDK | `.services.ai.azure.com` | DefaultAzureCredential | ✅ Sí |
| MAF | `.services.ai.azure.com` | DefaultAzureCredential | ✅ Sí |
| CrewAI | `.openai.azure.com` | DefaultAzureCredential (token) | ❌ No |

## Costes estimados

| Recurso | Coste aproximado |
|---------|------------------|
| AI Hub + Proyectos | ~$0/mes (solo metadata) |
| Storage Account | ~$1-5/mes |
| Key Vault | ~$0.03/10K operaciones |
| Application Insights | ~$2.30/GB ingestado |
| gpt-4o-mini | ~$0.15/1M tokens input, $0.60/1M output |

**Recomendación**: Ejecuta `destroy-all.ps1` cuando no estés usando el lab.

## Troubleshooting

### Error: "The subscription is not registered for namespace 'Microsoft.MachineLearningServices'"

```powershell
az provider register --namespace Microsoft.MachineLearningServices
```

### Error: "Quota exceeded"

Solicita aumento de cuota en el portal de Azure o usa otra región.

### Error: "Resource already exists"

Los scripts son idempotentes. Si el recurso existe, lo reutiliza.

### Deployment de modelo falla

Algunos modelos requieren creación manual desde el portal de AI Foundry:
1. Ve a https://ai.azure.com
2. Selecciona tu proyecto
3. Model catalog → Deploy model

## Estructura de archivos

```
infra/
├── config/
│   └── lab-config.ps1      # Variables centralizadas
├── scripts/
│   ├── 00-auth.ps1
│   ├── 01-resource-group.ps1
│   ├── 02-ai-hub.ps1
│   ├── 03-project-foundry.ps1
│   ├── 04-project-maf.ps1
│   ├── 05-project-crewai.ps1
│   ├── deploy-all.ps1
│   ├── destroy-all.ps1
│   └── show-endpoints.ps1
└── README.md               # Esta documentación
```
