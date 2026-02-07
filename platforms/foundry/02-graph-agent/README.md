# Foundry - Graph Agent

Agente con integración de Microsoft Graph usando Foundry SDK.

## Descripción
Agente capaz de interactuar con Microsoft Graph API para acceder a datos de calendario, correo, archivos, etc.

## Ejecución
```bash
# Instalar dependencias (desde la raíz del proyecto)
cd ../../..
pip install -r requirements.txt

# Ejecutar
cd platforms/foundry/02-graph-agent
python src/main.py
```

## Tests
```bash
pytest tests/
```
