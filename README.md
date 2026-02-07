
# ms-agents-ecosystem-lab

Laboratorio comparativo de agentes en el ecosistema Microsoft:
- **Microsoft Agent Framework (MAF)**
- **Microsoft Foundry SDK**
- **CrewAI** (con modelos alojados en Azure/OpenAI/Ollama)

## Objetivos
1. Entender implicaciones arquitectónicas de usar Foundry vs MAF vs CrewAI.
2. Medir complejidad, observabilidad, extensibilidad y coste.
3. Proveer ejemplos incrementales: **simple chat**, **Graph-enabled**, **orquestado**.

## Estructura del proyecto

```
ms-agents-ecosystem-lab/
├── platforms/                      # Implementaciones por framework
│   ├── foundry/                    # Microsoft Foundry SDK
│   │   ├── 01-simple-chat/
│   │   ├── 02-graph-agent/
│   │   └── 03-orchestrated/
│   ├── maf/                        # Microsoft Agent Framework
│   │   ├── 01-simple-chat/
│   │   ├── 02-graph-agent/
│   │   └── 03-orchestrated/
│   └── crewai/                     # CrewAI
│       ├── 01-simple-chat/
│       ├── 02-graph-agent/
│       └── 03-orchestrated/
├── infra/                          # Infraestructura como código
│   ├── config/                     # Configuración centralizada
│   │   └── lab-config.ps1
│   ├── scripts/                    # Scripts de despliegue
│   │   ├── 00-auth.ps1
│   │   ├── 01-resource-group.ps1
│   │   ├── 02-ai-hub.ps1
│   │   ├── 03-project-foundry.ps1
│   │   ├── 04-project-maf.ps1
│   │   ├── 05-project-crewai.ps1
│   │   ├── deploy-all.ps1
│   │   ├── destroy-all.ps1
│   │   └── show-endpoints.ps1
│   └── README.md
├── docs/                           # Documentación
│   └── azure-cli-auth.md           # Guía de autenticación Azure CLI
├── requirements.txt                # Dependencias Python (único para todo el proyecto)
├── .env.example                    # Plantilla de variables de entorno
├── .gitignore
└── README.md                       # Este archivo
```

## Cómo empezar

### 1. Requisitos previos

- **Azure CLI** con extensión ML:
  ```powershell
  az extension add --name ml
  ```
- **Python 3.10+**
- **Subscription de Azure** con permisos de Contributor

### 2. Autenticación

```powershell
# Login a tu tenant de Azure
az login --tenant <tu-tenant>

# Verificar cuenta y subscription
az account show --query "{Usuario:user.name, Subscription:name}" --output table
```

> 📖 Si trabajas con múltiples cuentas o tenants, consulta [docs/azure-cli-auth.md](docs/azure-cli-auth.md) para comandos de gestión de sesiones.

### 3. Configurar infraestructura

```powershell
# Copiar archivo de configuración
cd infra/config
copy lab-config.example.ps1 lab-config.ps1

# (Opcional) Editar lab-config.ps1 si necesitas cambiar región o nombres
```

### 4. Desplegar infraestructura

```powershell
cd ..\scripts
.\deploy-all.ps1
```

### 5. Configurar variables de entorno

```powershell
# Generar archivo .env con endpoints (desde infra/scripts)
.\show-endpoints.ps1

# Copiar a la raíz del proyecto
copy ..\..\.env.generated ..\..\.env
```

> 💡 Puedes revisar [.env.example](.env.example) para entender cada variable antes de ejecutar.

### 6. Instalar dependencias

```powershell
# Desde la raíz del proyecto
cd ..\..

# Crear entorno virtual (si no existe)
python -m venv .venv
.venv\Scripts\Activate.ps1

# Instalar todas las dependencias
pip install -r requirements.txt
```

> 📦 El archivo `requirements.txt` en la raíz contiene todas las dependencias organizadas por secciones (comunes, Foundry, MAF, CrewAI, desarrollo).

### 7. Ejecutar un proyecto

```powershell
# Asegúrate de tener el entorno virtual activado
cd platforms/foundry/01-simple-chat
python src/main.py
```

## Documentación

| Documento | Descripción |
|-----------|-------------|
| [infra/README.md](infra/README.md) | Guía completa de infraestructura, scripts y variables de conexión |
| [docs/azure-cli-auth.md](docs/azure-cli-auth.md) | Comandos de Azure CLI para gestionar múltiples cuentas y tenants |
| [.env.example](.env.example) | Plantilla de variables de entorno con descripción de cada una |

## Comparativa de frameworks

| Framework | Endpoint | Autenticación | Agentes en Foundry Portal |
|-----------|----------|---------------|---------------------------|
| **Foundry SDK** | `.services.ai.azure.com` | DefaultAzureCredential | ✅ Sí |
| **MAF** | `.services.ai.azure.com` | DefaultAzureCredential | ✅ Sí |
| **CrewAI** | `.openai.azure.com` | DefaultAzureCredential (token) | ❌ No |

> **Nota**: Foundry SDK y MAF crean agentes persistentes visibles en el portal de Azure AI Foundry. CrewAI usa el modelo desplegado pero los agentes solo existen en memoria durante la ejecución.

## Arquitectura en Azure

```
Resource Group: rg-agents-lab
└── AI Foundry Hub: hub-agents-lab
    ├── project-foundry-agents/    → Foundry SDK
    ├── project-maf-agents/        → MAF
    └── project-crewai-agents/     → CrewAI
```

## Limpieza

```powershell
cd infra/scripts
.\destroy-all.ps1
```

> ⚠️ **Recomendación**: Ejecuta `destroy-all.ps1` cuando no estés usando el laboratorio para evitar costes innecesarios. El modelo gpt-4o-mini tiene coste por uso (tokens consumidos).
