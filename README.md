
# ms-agents-ecosystem-lab

Laboratorio centrado en **Microsoft Agent Framework (MAF)** sobre Azure AI Foundry.

## Objetivos
1. Probar rápidamente un entorno MAF completo en Azure AI Foundry.
2. Ejecutar ejemplos incrementales (simple chat, graph, orquestado) sobre un único recurso Foundry.
3. Mantener scripts de infraestructura mínimos y reproducibles.

## Estructura del proyecto

```
ms-agents-ecosystem-lab/
├── platforms/
│   └── maf/
│       ├── 01-simple-chat/
│       ├── 02-graph-agent/
│       └── 03-orchestrated/
├── infra/
│   ├── config/
│   │   └── lab-config.ps1
│   └── scripts/
│       ├── 00-auth.ps1
│       ├── 01-resource-group.ps1
│       ├── 02-foundry-maf.ps1
│       ├── deploy-all.ps1
│       ├── destroy-all.ps1
│       └── show-endpoints.ps1
├── docs/
│   └── azure-cli-auth.md
├── requirements.txt
├── .env.example
└── README.md
```

## Cómo empezar

### 1. Requisitos previos
- Azure CLI instalada (no requiere extensión ML)
- Python 3.10+
- Rol Contributor en la subscription de Azure

### 2. Autenticación
```powershell
az login --tenant <tu-tenant>
az account show --query "{Usuario:user.name, Subscription:name}" --output table
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
.\show-endpoints.ps1
copy ..\..\.env.generated ..\..\.env
```
Consulta [.env.example](.env.example) para conocer cada variable.

### 6. Instalar dependencias
```powershell
cd ..\..
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### 7. Ejecutar un ejemplo
```powershell
cd platforms/maf/01-simple-chat
python src/main.py
```

## Arquitectura en Azure

```
Resource Group: rg-agents-lab
└── Foundry (AIServices): foundry-maf-lab
    ├── Proyecto de agentes: foundry-maf-lab-project
    └── Deployment: gpt-4o-mini
```

## Limpieza
```powershell
cd infra/scripts
.\destroy-all.ps1
```
Confirma escribiendo `ELIMINAR` cuando se solicite para evitar costes innecesarios.
