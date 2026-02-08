# Arquitectura de Azure AI Foundry

Este documento explica la arquitectura de Azure AI Foundry, los componentes del Hub, la diferencia entre modelos Serverless y Azure OpenAI (Cognitive Services), y los permisos necesarios para trabajar con cada uno.

## Indice

1. [Vision general](#vision-general)
2. [Componentes del Hub](#componentes-del-hub)
3. [Recursos compartidos vs heredados](#recursos-compartidos-vs-heredados)
4. [Modelos: Serverless vs Azure OpenAI](#modelos-serverless-vs-azure-openai)
5. [Roles y permisos](#roles-y-permisos)
6. [Autenticacion](#autenticacion)
7. [Endpoints y conexiones](#endpoints-y-conexiones)
8. [Consideraciones de coste](#consideraciones-de-coste)

---

## Vision general

Azure AI Foundry es la plataforma unificada de Microsoft para desarrollar aplicaciones de IA. Organiza los recursos en una jerarquia:

```
Azure Subscription
    │
    └── Resource Group
            │
            ├── AI Foundry Hub (recursos compartidos)
            │       │
            │       ├── Proyecto 1 (hereda del Hub)
            │       ├── Proyecto 2 (hereda del Hub)
            │       └── Proyecto N (hereda del Hub)
            │
            └── Azure OpenAI (Cognitive Services)
                    └── Modelos desplegados
```

---

## Componentes del Hub

### Recursos que crea el Hub

| Recurso | Tipo | Proposito |
|---------|------|-----------|
| **Storage Account** | `Microsoft.Storage/storageAccounts` | Almacena datos, modelos, logs |
| **Key Vault** | `Microsoft.KeyVault/vaults` | Secretos, claves API, certificados |
| **Application Insights** | `Microsoft.Insights/components` | Telemetria, metricas, trazas |
| **Log Analytics** | `Microsoft.OperationalInsights/workspaces` | Logs centralizados |

### Recursos externos (se conectan al Hub)

| Recurso | Tipo | Proposito |
|---------|------|-----------|
| **Azure OpenAI** | `Microsoft.CognitiveServices/accounts` | Modelos GPT, DALL-E, Embeddings |
| **Azure AI Search** | `Microsoft.Search/searchServices` | Busqueda vectorial (RAG) |
| **Azure Cosmos DB** | `Microsoft.DocumentDB/databaseAccounts` | Almacenamiento de conversaciones |

---

## Recursos compartidos vs heredados

### Diagrama de herencia

```
┌─────────────────────────────────────────────────────────────────┐
│                        HUB (hub-agents-lab)                      │
│                                                                  │
│  RECURSOS PROPIOS (creados con el Hub):                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │   Storage    │ │   Key Vault  │ │ App Insights │             │
│  │  Account     │ │              │ │              │             │
│  └──────────────┘ └──────────────┘ └──────────────┘             │
│                                                                  │
│  CONEXIONES (a recursos externos):                              │
│  ┌──────────────────────────────────────────────────┐           │
│  │  aoai-connection → aoai-agents-lab               │           │
│  │  (Azure OpenAI con gpt-4o-mini)                  │           │
│  └──────────────────────────────────────────────────┘           │
│                           │                                      │
│              ┌────────────┴────────────┐                        │
│              │     HERENCIA            │                        │
│              ▼            ▼            ▼                        │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │  project-    │ │  project-    │ │  project-    │             │
│  │  langchain   │ │  maf         │ │  crewai      │             │
│  │              │ │              │ │              │             │
│  │ Hereda:      │ │ Hereda:      │ │ Hereda:      │             │
│  │ - Storage    │ │ - Storage    │ │ - Storage    │             │
│  │ - Key Vault  │ │ - Key Vault  │ │ - Key Vault  │             │
│  │ - Conexiones │ │ - Conexiones │ │ - Conexiones │             │
│  └──────────────┘ └──────────────┘ └──────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

### Que se hereda automaticamente

| Recurso/Conexion | Se hereda | Notas |
|------------------|-----------|-------|
| Storage Account | Si | Todos los proyectos comparten el mismo storage |
| Key Vault | Si | Secretos accesibles desde todos los proyectos |
| Application Insights | Si | Telemetria centralizada |
| Conexiones Azure OpenAI | Si | El modelo es accesible desde todos los proyectos |
| Conexiones AI Search | Si | Indice compartido para RAG |
| Compute instances | No | Cada proyecto puede tener su propio compute |
| Datasets | Parcial | Depende de permisos y ubicacion |

### Ventajas de la herencia

1. **Gestion centralizada**: Un solo lugar para configurar conexiones
2. **Reduccion de costes**: Recursos compartidos, no duplicados
3. **Consistencia**: Todos los proyectos usan la misma configuracion
4. **Seguridad**: Permisos gestionados a nivel de Hub

---

## Modelos: Serverless vs Azure OpenAI

### Por que existen dos tipos?

La separacion existe por razones **contractuales, tecnicas y de negocio**:

#### Historia

| Año | Evento |
|-----|--------|
| 2019 | Microsoft invierte $1B en OpenAI |
| 2020 | Microsoft obtiene licencia **exclusiva** para GPT-3 |
| 2021 | Lanza Azure OpenAI Service (Cognitive Services) |
| 2023 | Microsoft invierte $10B adicionales en OpenAI |
| 2023 | Lanza Model Catalog con modelos de terceros |
| 2024 | Unifica bajo "AI Foundry" (pero la separacion tecnica persiste) |

### Comparativa detallada

| Aspecto | Azure OpenAI (Cognitive Services) | Serverless Endpoints (ML) |
|---------|-----------------------------------|---------------------------|
| **Modelos** | GPT-4, GPT-4o, GPT-4o-mini, DALL-E, Whisper, Embeddings | Llama, Mistral, Phi, Cohere, etc. |
| **Proveedor** | OpenAI (via Microsoft) | Meta, Mistral AI, Microsoft, otros |
| **Licencia** | Exclusiva Microsoft-OpenAI | Marketplace abierto |
| **Comando CLI** | `az cognitiveservices` | `az ml serverless-endpoint` |
| **Tipo de recurso** | `Microsoft.CognitiveServices/accounts` | Dentro del ML Workspace |
| **Endpoint** | `*.openai.azure.com` | `*.inference.ml.azure.com` |
| **SDK Python** | `openai` (AzureOpenAI) | `azure-ai-inference` |
| **Content filtering** | Obligatorio (integrado) | Opcional |
| **SLA** | 99.9% | Variable por modelo |
| **Regiones** | Limitadas | Mas regiones disponibles |
| **Compliance** | SOC2, HIPAA, ISO 27001 | Varia por proveedor |

### Diagrama de arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                         AZURE AI                                 │
│                                                                  │
│  ┌─────────────────────────┐    ┌─────────────────────────────┐ │
│  │   AZURE OPENAI SERVICE  │    │   MODEL CATALOG (Serverless) │ │
│  │   (Cognitive Services)  │    │   (AI Foundry / ML)          │ │
│  │                         │    │                               │ │
│  │  ┌───────────────────┐  │    │  ┌───────────────────────┐   │ │
│  │  │ Modelos OpenAI    │  │    │  │ Modelos Terceros      │   │ │
│  │  │ - GPT-4           │  │    │  │ - Llama (Meta)        │   │ │
│  │  │ - GPT-4o          │  │    │  │ - Mistral             │   │ │
│  │  │ - GPT-4o-mini     │  │    │  │ - Phi (Microsoft)     │   │ │
│  │  │ - DALL-E          │  │    │  │ - Cohere              │   │ │
│  │  │ - Whisper         │  │    │  │ - AI21                │   │ │
│  │  │ - text-embedding  │  │    │  └───────────────────────┘   │ │
│  │  └───────────────────┘  │    │                               │ │
│  │                         │    │  Comando:                     │ │
│  │  Comando:               │    │  az ml serverless-endpoint    │ │
│  │  az cognitiveservices   │    │                               │ │
│  │                         │    │  Endpoint:                    │ │
│  │  Endpoint:              │    │  *.inference.ml.azure.com     │ │
│  │  *.openai.azure.com     │    │                               │ │
│  └─────────────────────────┘    └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Modelo de ingresos

```
                    INGRESOS POR USO
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ▼               ▼               ▼
     ┌─────────┐    ┌──────────┐    ┌──────────┐
     │ OpenAI  │    │ Microsoft│    │ Terceros │
     │ (GPT)   │    │ (Phi)    │    │ (Llama)  │
     └────┬────┘    └────┬─────┘    └────┬─────┘
          │              │               │
          ▼              ▼               ▼
     Microsoft      Microsoft        Revenue
     paga royalty   margen 100%      sharing
     a OpenAI                        con Meta/etc
```

---

## Roles y permisos

### Roles para Azure OpenAI (Cognitive Services)

| Rol | Permite | Scope tipico |
|-----|---------|--------------|
| `Cognitive Services OpenAI User` | Llamar a la API (usar modelos) | Recurso Azure OpenAI |
| `Cognitive Services OpenAI Contributor` | + Crear/modificar deployments | Recurso Azure OpenAI |
| `Cognitive Services Contributor` | + Crear el recurso Azure OpenAI | Resource Group |

### Roles para Serverless Endpoints (ML)

| Rol | Permite | Scope tipico |
|-----|---------|--------------|
| `AzureML Data Scientist` | Crear/usar serverless endpoints | ML Workspace/Project |
| `AzureML Compute Operator` | Gestionar compute | ML Workspace |
| `Contributor` | Control total del workspace | ML Workspace |

### Roles para AI Foundry Hub/Projects

| Rol | Permite | Scope tipico |
|-----|---------|--------------|
| `Azure AI Developer` | Desarrollar en proyectos | Hub o Project |
| `Azure AI Inference Deployment Operator` | Desplegar modelos | Hub o Project |
| `Contributor` | Control total | Resource Group |

### Matriz de permisos por caso de uso

| Caso de uso | Roles necesarios |
|-------------|------------------|
| Solo usar GPT desde codigo | `Cognitive Services OpenAI User` |
| Desplegar nuevos modelos GPT | `Cognitive Services OpenAI Contributor` |
| Crear recurso Azure OpenAI | `Cognitive Services Contributor` |
| Usar Llama/Mistral | `AzureML Data Scientist` |
| Crear proyectos en AI Foundry | `Azure AI Developer` + `Contributor` |
| Gestionar Hub completo | `Contributor` en Resource Group |

### Asignar roles via CLI

```powershell
# Obtener el Object ID del usuario
$userId = az ad signed-in-user show --query id -o tsv

# Rol para usar Azure OpenAI
az role assignment create `
    --assignee $userId `
    --role "Cognitive Services OpenAI User" `
    --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{aoai}"

# Rol para AI Foundry
az role assignment create `
    --assignee $userId `
    --role "Azure AI Developer" `
    --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.MachineLearningServices/workspaces/{hub}"
```

---

## Autenticacion

### DefaultAzureCredential (recomendado)

Funciona automaticamente con multiples fuentes de credenciales:

```python
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()
# Intenta en orden:
# 1. Environment variables
# 2. Managed Identity
# 3. Visual Studio Code
# 4. Azure CLI
# 5. Azure PowerShell
# 6. Interactive browser
```

### Para Azure OpenAI

```python
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

credential = DefaultAzureCredential()
token_provider = get_bearer_token_provider(
    credential, 
    "https://cognitiveservices.azure.com/.default"
)

client = AzureOpenAI(
    azure_endpoint="https://aoai-agents-lab.openai.azure.com",
    azure_ad_token_provider=token_provider,
    api_version="2024-02-15-preview"
)
```

### Para Serverless Endpoints

```python
from azure.ai.inference import ChatCompletionsClient
from azure.identity import DefaultAzureCredential

client = ChatCompletionsClient(
    endpoint="https://project-name.inference.ml.azure.com",
    credential=DefaultAzureCredential()
)
```

### Para MAF (Microsoft Agent Framework)

```python
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

project = AIProjectClient(
    credential=DefaultAzureCredential(),
    endpoint="https://project-maf-agents.services.ai.azure.com"
)

# Los agentes creados aparecen en el portal de AI Foundry
agent = project.agents.create_agent(
    model="gpt-4o-mini",
    name="mi-agente"
)
```

---

## Endpoints y conexiones

### Tipos de endpoints

| Tipo | Formato | Uso |
|------|---------|-----|
| Azure OpenAI | `https://{resource}.openai.azure.com` | SDK de OpenAI |
| Project Services | `https://{project}.services.ai.azure.com` | MAF, Agents |
| ML Inference | `https://{project}.inference.ml.azure.com` | Serverless |
| Management | `https://{location}.api.azureml.ms` | CLI, SDK de ML |

### Conexiones en el Hub

Las conexiones permiten que el Hub y sus proyectos accedan a recursos externos:

```yaml
# Ejemplo de conexion Azure OpenAI
name: aoai-connection
type: azure_open_ai
azure_endpoint: https://aoai-agents-lab.openai.azure.com/
api_key: <key>  # O usar Managed Identity
```

### Crear conexion via CLI

```powershell
# Crear archivo YAML
$connectionYaml = @"
name: aoai-connection
type: azure_open_ai
azure_endpoint: https://aoai-agents-lab.openai.azure.com/
api_key: $aoaiKey
"@

$connectionYaml | Out-File -FilePath connection.yaml -Encoding utf8

# Crear conexion en el Hub
az ml connection create `
    --file connection.yaml `
    --resource-group rg-agents-lab `
    --workspace-name hub-agents-lab
```

---

## Consideraciones de coste

### Azure OpenAI (GPT-4o-mini)

| Metrica | Precio aproximado |
|---------|-------------------|
| Input tokens | $0.15 / 1M tokens |
| Output tokens | $0.60 / 1M tokens |
| TPM base | 10K incluidos |

### Serverless (Llama 3.2 3B)

| Metrica | Precio aproximado |
|---------|-------------------|
| Input tokens | $0.06 / 1M tokens |
| Output tokens | $0.06 / 1M tokens |

### Recursos del Hub

| Recurso | Coste |
|---------|-------|
| Storage Account | ~$0.02/GB/mes |
| Key Vault | ~$0.03/10K operaciones |
| Application Insights | ~$2.30/GB ingestado |
| Log Analytics | ~$2.76/GB ingestado |

### Recomendaciones

1. **Para desarrollo/labs**: Usar GPT-4o-mini o Llama 3.2 (bajo coste)
2. **Para produccion**: Evaluar coste vs calidad segun caso de uso
3. **Monitorizar**: Usar Application Insights para tracking de tokens
4. **Quotas**: Configurar limites de TPM para evitar sorpresas

---

## Referencias

- [Azure AI Foundry documentation](https://learn.microsoft.com/azure/ai-studio/)
- [Azure OpenAI Service](https://learn.microsoft.com/azure/ai-services/openai/)
- [Model catalog](https://learn.microsoft.com/azure/ai-studio/how-to/model-catalog)
- [Azure RBAC for AI services](https://learn.microsoft.com/azure/ai-services/authentication)
- [DefaultAzureCredential](https://learn.microsoft.com/python/api/azure-identity/azure.identity.defaultazurecredential)
