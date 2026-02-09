# Arquitectura de Azure AI Foundry (lab)

Documento alineado con la infraestructura actual del proyecto: **solo** recursos de Azure AI Foundry y un despliegue de **gpt-4o-mini** por proyecto. No usamos Azure AI Search, Cosmos DB, endpoints serverless ni otros servicios externos.

## Indice

1. [Vision general](#vision-general)
2. [Recursos desplegados](#recursos-desplegados)
3. [Modelos y endpoints](#modelos-y-endpoints)
4. [Roles y permisos](#roles-y-permisos)
5. [Autenticacion](#autenticacion)
6. [Costes estimados](#costes-estimados)
7. [Referencias](#referencias)

---

## Vision general

Arquitectura actual del lab:

```
Resource Group: rg-agents-lab
└── AI Foundry Hub: hub-agents-lab
    ├── project-langchain-agents   → gpt-4o-mini
    ├── project-maf-agents         → gpt-4o-mini
    └── project-crewai-agents      → gpt-4o-mini

Recursos compartidos creados por el Hub:
├── Storage Account
├── Key Vault
├── Application Insights
└── Log Analytics Workspace
```

Principios del despliegue:

- Un unico hub de Azure AI Foundry con tres proyectos (LangChain, MAF, CrewAI).
- Cada proyecto despliega un unico modelo **gpt-4o-mini** (Azure OpenAI) accesible desde los frameworks.
- Sin conexiones externas (AI Search, Cosmos DB) ni serverless endpoints; todo se apoya en los recursos propios del Hub.

---

## Recursos desplegados

| Recurso | Tipo | Proposito | Creador |
|---------|------|-----------|---------|
| Resource Group | `Microsoft.Resources/resourceGroups` | Contenedor comun | Script `01-resource-group.ps1` |
| AI Foundry Hub | `Microsoft.MachineLearningServices/workspaces` | Punto central de proyectos y conexiones | Script `02-ai-hub.ps1` |
| Storage Account | `Microsoft.Storage/storageAccounts` | Datos y logs del hub | Creado automaticamente por el Hub |
| Key Vault | `Microsoft.KeyVault/vaults` | Secretos y claves | Creado automaticamente por el Hub |
| Application Insights | `Microsoft.Insights/components` | Telemetria | Creado automaticamente por el Hub |
| Log Analytics | `Microsoft.OperationalInsights/workspaces` | Logs centralizados | Creado automaticamente por el Hub |
| project-langchain-agents | Proyecto de Foundry | Experimentos con LangChain | Script `03-project-langchain.ps1` |
| project-maf-agents | Proyecto de Foundry | Experimentos con Microsoft Agent Framework | Script `04-project-maf.ps1` |
| project-crewai-agents | Proyecto de Foundry | Experimentos con CrewAI | Script `05-project-crewai.ps1` |
| Despliegue gpt-4o-mini | Azure OpenAI deployment | Modelo unico por proyecto | Scripts de proyecto |

Recursos **no** desplegados en este lab: Azure AI Search, Cosmos DB, serverless endpoints del model catalog, conexiones a recursos externos.

---

## Modelos y endpoints

- Modelo unico: **gpt-4o-mini** (Azure OpenAI) desplegado dentro de cada proyecto de Foundry.
- Endpoints generados:
  - `.openai.azure.com` para llamadas compatibles con OpenAI (LangChain, CrewAI).
  - `.services.ai.azure.com` para el servicio de agentes (MAF) cuando aplica.
- Variables de entorno generadas por `show-endpoints.ps1` (ejemplos):
  - `LANGCHAIN_ENDPOINT`, `LANGCHAIN_DEPLOYMENT_NAME`
  - `MAF_ENDPOINT`, `MAF_DEPLOYMENT_NAME`
  - `CREWAI_ENDPOINT`, `CREWAI_DEPLOYMENT_NAME`

No se usan endpoints serverless (`*.inference.ml.azure.com`) ni conexiones adicionales.

---

## Roles y permisos

Permisos minimos para operar el lab:

- `Contributor` en el Resource Group para crear y eliminar el hub y proyectos.
- `Azure AI Developer` en el Hub o en cada proyecto para trabajar con despliegues y endpoints.
- `Cognitive Services OpenAI User` en el recurso de Azure OpenAI subyacente (para invocar gpt-4o-mini mediante token AAD).

No se requieren roles de AzureML para serverless ni permisos sobre recursos externos, porque no se usan.

Asignacion via CLI (ejemplo):

```powershell
$userId = az ad signed-in-user show --query id -o tsv

az role assignment create `
    --assignee $userId `
    --role "Azure AI Developer" `
    --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.MachineLearningServices/workspaces/{hub}"

az role assignment create `
    --assignee $userId `
    --role "Cognitive Services OpenAI User" `
    --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{aoai}"
```

---

## Autenticacion

Todas las SDK usan `DefaultAzureCredential` con Azure AD; no almacenamos API keys.

```python
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

credential = DefaultAzureCredential()
token_provider = get_bearer_token_provider(
    credential,
    "https://cognitiveservices.azure.com/.default"
)

client = AzureOpenAI(
    azure_endpoint="https://<project>.openai.azure.com",
    azure_deployment="gpt-4o-mini",
    azure_ad_token_provider=token_provider,
    api_version="2024-02-15-preview"
)
```

Para MAF, se usa el mismo `DefaultAzureCredential` apuntando al endpoint del proyecto (`*.services.ai.azure.com`).

---

## Costes estimados

| Recurso | Coste aproximado |
|---------|------------------|
| AI Hub + Proyectos | ~$0/mes (metadata) |
| Storage Account | ~$1-5/mes |
| Key Vault | ~$0.03/10K operaciones |
| Application Insights | ~$2.30/GB ingestado |
| gpt-4o-mini | ~$0.15/1M tokens input, $0.60/1M tokens output |

Recomendacion: destruir el Resource Group con `destroy-all.ps1` cuando no se use el lab.

---

## Referencias

- [Azure AI Foundry documentation](https://learn.microsoft.com/azure/ai-studio/)
- [Azure OpenAI Service](https://learn.microsoft.com/azure/ai-services/openai/)
- [DefaultAzureCredential](https://learn.microsoft.com/python/api/azure-identity/azure.identity.defaultazurecredential)