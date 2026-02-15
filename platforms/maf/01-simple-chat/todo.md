# TODO: MAF Simple Chat Web API + Azure Deployment

## 📋 Objetivo Final
Desplegar el agente MAF como servicio web en Azure App Service con identidad administrada para acceso a Azure AI Services.

---

## ✅ Estructura Local (Production-Ready)

```
platforms/maf/01-simple-chat/
├── main.py                    # CLI entry (local dev)
├── run_web.py                # Web entry (local dev + Azure)
├── wsgi.py                   # WSGI para Azure App Service
│
├── app/
│   ├── __init__.py
│   ├── core/
│   │   ├── __init__.py
│   │   ├── interfaces.py
│   │   └── agent.py          # ⭐ SimpleChatAgent (sin cambios)
│   │
│   └── ui/
│       ├── __init__.py
│       ├── cli.py            # Terminal interactivo
│       ├── web.py            # FastAPI app
│       └── schemas.py        # Pydantic models (request/response)
│
├── config/
│   ├── __init__.py
│   └── settings.py           # Variables de entorno (Pydantic)
│
├── tests/
│   ├── unit/
│   └── integration/
│
├── .env.example
├── requirements.txt
├── requirements-dev.txt       # pytest, black (dev only)
├── startup.sh                # Script de inicio para Azure
├── .gitignore
└── README.md
```

---

## 🛠️ Tareas a Implementar

### [ ] 1. Crear `app/config/settings.py`

**Propósito**: Gestionar variables de entorno con validación Pydantic

```python
# filepath: platforms/maf/01-simple-chat/app/config/settings.py
"""Configuration management for Azure deployment."""
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Load env vars with type validation."""
    
    # MAF Configuration
    endpoint_api: str
    deployment_name: str
    project_name: str
    api_version: str | None = "2024-10-21"
    api_key: str | None = None
    
    # Web Configuration
    environment: str = "development"  # development, production
    debug: bool = False
    
    class Config:
        env_file = ".env"
        case_sensitive = False

@lru_cache
def get_settings() -> Settings:
    return Settings()
```

---

### [ ] 2. Crear `app/ui/schemas.py`

**Propósito**: Modelos Pydantic para request/response REST

```python
# filepath: platforms/maf/01-simple-chat/app/ui/schemas.py
"""Pydantic models for REST API."""
from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    """Request model for /chat endpoint."""
    message: str = Field(..., min_length=1, max_length=2000)
    
    class Config:
        json_schema_extra = {
            "example": {
                "message": "¿Cuál es el lenguaje de programación más utilizado?"
            }
        }


class ChatResponse(BaseModel):
    """Response model for /chat endpoint."""
    success: bool
    message: str
    error: str | None = None
    
    class Config:
        json_schema_extra = {
            "example": {
                "success": True,
                "message": "JavaScript es el más utilizado en web...",
                "error": None
            }
        }
```

---

### [ ] 3. Crear `app/ui/web.py`

**Propósito**: FastAPI app con endpoints REST

```python
# filepath: platforms/maf/01-simple-chat/app/ui/web.py
"""FastAPI web interface for MAF agent."""
import logging
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.core.agent import SimpleChatAgent
from app.config.settings import get_settings
from app.ui.schemas import ChatRequest, ChatResponse

logger = logging.getLogger(__name__)
settings = get_settings()

# Initialize FastAPI
app = FastAPI(
    title="MAF Simple Chat API",
    version="1.0.0",
    description="Microsoft Agent Framework Chat API"
)

# CORS for Azure App Service
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restringir en producción
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global agent instance (inicializado en startup)
agent: SimpleChatAgent | None = None


@app.on_event("startup")
async def startup():
    """Initialize agent on server startup."""
    global agent
    try:
        agent = SimpleChatAgent()
        await agent.initialize()
        logger.info("✅ Agent initialized on startup")
    except Exception as e:
        logger.error(f"Failed to initialize agent: {e}", exc_info=True)
        raise


@app.on_event("shutdown")
async def shutdown():
    """Cleanup agent on server shutdown."""
    global agent
    if agent:
        await agent.cleanup()
        logger.info("✅ Agent cleaned up on shutdown")


@app.get("/health")
async def health_check():
    """Health check endpoint for Azure App Service."""
    return {
        "status": "healthy",
        "environment": settings.environment,
        "agent_ready": agent is not None
    }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest) -> ChatResponse:
    """
    Process user message through MAF agent.
    
    Args:
        request: ChatRequest with user message
    
    Returns:
        ChatResponse with agent response
        
    Raises:
        HTTPException: If agent not initialized or processing fails
    """
    global agent
    
    if agent is None:
        logger.error("Agent not initialized")
        raise HTTPException(status_code=503, detail="Agent not initialized")
    
    try:
        logger.debug(f"Processing message: {request.message}")
        response_text = await agent.process_user_message(request.message)
        
        return ChatResponse(
            success=True,
            message=response_text,
            error=None
        )
    except Exception as e:
        logger.error(f"Error processing message: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Error processing message: {str(e)}"
        )


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "message": "MAF Simple Chat API",
        "docs": "/docs",
        "health": "/health"
    }
```

---

### [ ] 4. Actualizar `requirements.txt`

```txt
# Core
azure-ai-projects==0.20.0
azure-identity==1.15.0
python-dotenv==1.0.0

# Web
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic-settings==2.1.0
gunicorn==21.2.0

# Optional: Production
# slowapi==0.1.9  # Rate limiting
```

---

### [ ] 5. Crear `run_web.py` (En raíz del proyecto)

**Propósito**: Entry point para desarrollo web local

```python
# filepath: platforms/maf/01-simple-chat/run_web.py
"""Web API entry point for local development."""
import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "app.ui.web:app",
        host="127.0.0.1",
        port=8000,
        reload=True,
        log_level="info"
    )
```

---

### [ ] 6. Crear `wsgi.py` (En raíz del proyecto)

**Propósito**: Entry point para Azure App Service

```python
# filepath: platforms/maf/01-simple-chat/wsgi.py
"""WSGI entry point for Azure App Service."""
from app.ui.web import app

# Azure App Service busca 'application' por defecto
application = app
```

---

### [ ] 7. Crear `startup.sh` (En raíz del proyecto)

**Propósito**: Script de inicialización para Azure App Service

```bash
#!/bin/bash
pip install --upgrade pip
pip install -r requirements.txt
gunicorn --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 wsgi:application
```

---

### [ ] 8. Crear `app/config/__init__.py`

```python
"""Configuration module."""
from app.config.settings import get_settings, Settings

__all__ = ["get_settings", "Settings"]
```

---

### [ ] 9. Verificar Importes en `app/core/agent.py`

**Cambio requerido**: Actualizar path raíz del proyecto

Línea actual:
```python
PROJECT_ROOT = Path(__file__).resolve().parents[5]
```

Debe permanecer igual (5 niveles hacia arriba sigue siendo correcto: `agent.py` → `core/` → `app/` → `01-simple-chat/` → `maf/` → `platforms/`)

---

## 🧪 Verificación Local

### Terminal 1: Ejecutar CLI
```bash
cd platforms/maf/01-simple-chat
python main.py
```

### Terminal 2: Ejecutar Web API
```bash
cd platforms/maf/01-simple-chat
python run_web.py
```

### Terminal 3: Probar Endpoints
```bash
# Health check
curl http://localhost:8000/health

# Chat request
curl -X POST "http://localhost:8000/chat" \
  -H "Content-Type: application/json" \
  -d '{"message":"Hola agente"}'

# OpenAPI docs
# Abre en navegador: http://localhost:8000/docs
```

---

## 🚀 Despliegue en Azure App Service

### Paso 1: Crear App Service (desde Azure Portal o CLI)

```powershell
# Variables
$resourceGroup = "maf-rg"
$appServiceName = "foundry-maf-chat-api"
$appServicePlan = "maf-plan"

# Crear App Service Plan
az appservice plan create `
  --name $appServicePlan `
  --resource-group $resourceGroup `
  --sku B1 `
  --is-linux

# Crear App Service
az webapp create `
  --resource-group $resourceGroup `
  --name $appServiceName `
  --plan $appServicePlan `
  --runtime "PYTHON|3.11"
```

---

### Paso 2: Asignar Identidad Administrada

```powershell
# Asignar managed identity
az webapp identity assign `
  --resource-group $resourceGroup `
  --name $appServiceName `
  --identities [system]

# Obtener Object ID
$principalId = (az webapp identity show `
  --resource-group $resourceGroup `
  --name $appServiceName `
  --query principalId -o tsv)

# Asignar rol a Azure AI Services
$aiServicesScope = "/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<ai-services-name>"

az role assignment create `
  --assignee $principalId `
  --role "Cognitive Services User" `
  --scope $aiServicesScope
```

---

### Paso 3: Configurar Variables de Entorno (Azure Portal)

**Ir a**: App Service → Configuration → Application settings

```
ENDPOINT_API=https://foundry-maf-lab.services.ai.azure.com
DEPLOYMENT_NAME=gpt-4o-mini
PROJECT_NAME=foundry-maf-lab-project
API_VERSION=2024-10-21
ENVIRONMENT=production
DEBUG=False
```

**❌ Importante**: NO incluir `API_KEY` (usa identidad administrada)

---

### Paso 4: Configurar Startup Command (Azure Portal)

**Ir a**: App Service → Configuration → General settings → Startup Command

```
gunicorn --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 wsgi:application
```

---

### Paso 5: Conectar Repositorio GitHub (Azure Portal)

1. **Ir a**: App Service → Deployment Center
2. **Seleccionar**: GitHub
3. **Autorizar** y seleccionar:
   - Repository: `ms-agents-ecosystem-lab`
   - Branch: `main`
   - Build provider: GitHub Actions (recomendado)

---

### Paso 6: Configurar GitHub Actions (Automático)

Azure crea `.github/workflows/azure-webapps-python.yml` automáticamente. Verificar que:

```yaml
- name: Deploy to Azure Web App
  uses: azure/webapps-deploy@v2
  with:
    app-name: ${{ env.AZURE_WEBAPP_NAME }}
    slot-name: production
    publish-profile: ${{ secrets.AZURE_WEBAPP_PUBLISH_PROFILE }}
    package: platforms/maf/01-simple-chat
```

---

## 🔐 Diferencias: Desarrollo vs Producción

### Desarrollo Local
```env
ENDPOINT_API=https://foundry-maf-lab.services.ai.azure.com
DEPLOYMENT_NAME=gpt-4o-mini
PROJECT_NAME=maf
API_VERSION=2024-10-21
API_KEY=sk-xxx-xxx  # ✅ Permitido (solo local)
ENVIRONMENT=development
DEBUG=True
```

### Producción (Azure)
```
ENDPOINT_API=https://foundry-maf-lab.services.ai.azure.com
DEPLOYMENT_NAME=gpt-4o-mini
PROJECT_NAME=foundry-maf-lab-project
API_VERSION=2024-10-21
ENVIRONMENT=production
DEBUG=False
# ❌ NO API_KEY (usa Managed Identity automáticamente)
```

---

## 📡 Flujo de Despliegue

```
Local Development
├── python main.py (CLI)
├── python run_web.py (FastAPI local)
└── .env (con API_KEY)
    ↓
    git commit && git push
    ↓
GitHub (rama main)
    ↓
GitHub Actions (Workflow)
    ↓
Azure App Service Deploy
├── wsgi.py (Entry point)
├── gunicorn (App Server)
├── startup.sh (Initialization)
└── Managed Identity (Azure Auth)
    ↓
✅ Endpoint: https://foundry-maf-chat-api.azurewebsites.net
├── GET  /health → Health check
├── POST /chat → Chat endpoint
├── GET  /docs → Swagger UI
└── GET  /openapi.json → OpenAPI spec
```

---

## ✅ Verificación Post-Deploy

```bash
# Antes de desplegar en Azure, verificar localmente:

# 1. Instalar dependencias
pip install -r requirements.txt

# 2. Probar CLI
python main.py

# 3. Probar Web (en otra terminal)
python run_web.py

# 4. Probar endpoints
curl http://localhost:8000/health
curl -X POST http://localhost:8000/chat -H "Content-Type: application/json" -d '{"message":"Hola"}'

# 5. Ver OpenAPI docs
# http://localhost:8000/docs
```

---

## 🐛 Troubleshooting

### Error: `ModuleNotFoundError: No module named 'fastapi'`
```bash
pip install -r requirements.txt
```

### Error: `Module named 'app.config' not found`
- Verificar que `app/config/__init__.py` existe
- Verificar que se ejecuta desde `platforms/maf/01-simple-chat/`

### Error: `Agent not initialized` en Azure
1. Verificar que `ENDPOINT_API`, `DEPLOYMENT_NAME` están en App Service Configuration
2. Verificar que Managed Identity tiene roles en Azure AI Services
3. Revisar logs en Azure Portal → Diagnose and solve problems

### Azure App Service no inicia
1. Revisar logs: Azure Portal → Log stream
2. Ejecutar localmente con `DEBUG=True` para más detalles
3. Verificar que `gunicorn` está en `requirements.txt`

---

## 📚 Próximos Pasos Opcionales

- [ ] Añadir Rate Limiting: `slowapi`
- [ ] Añadir JWT Auth: `python-jose`, `passlib`
- [ ] Añadir DB (conversation history): `sqlalchemy`, `alembic`
- [ ] Añadir tests de API: `pytest-asyncio`, `httpx`
- [ ] Añadir logging a Application Insights: `azure-monitor-opentelemetry`
- [ ] Añadir CI/CD tests: GitHub Actions con `pytest`

---

## 📝 Notas Importantes

1. **Identidad Administrada**: Azure maneja automáticamente credenciales. No necesita API_KEY en producción
2. **CORS**: Cambiar `allow_origins=["*"]` a dominios específicos en producción
3. **Workers**: `--workers 4` depende del tier de App Service. Ajustar según necesidad
4. **Health Check**: Azure usa `/health` para liveness probes automáticamente
5. **Escalado**: App Service puede escalar automáticamente basado en CPU/Memory

---

## 📞 Contacto & Referencias

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Azure App Service Python](https://learn.microsoft.com/en-us/azure/app-service/quickstart-python)
- [Microsoft Agent Framework](https://aka.ms/agent-framework-docs)
- [Pydantic Settings](https://docs.pydantic.dev/latest/concepts/pydantic_settings/)

