# MAF - Simple Chat

Agente básico de chat usando Microsoft Agent Framework (MAF) sobre Azure AI Foundry. Ejecuta un bucle interactivo contra un deployment de OpenAI en un proyecto Foundry.

## Descripción
Implementación mínima: lee los endpoints desde `.env`, usa `AzureCliCredential` (sesión `az login`) y envía mensajes al deployment configurado. No crea recursos de agente en Foundry; simplemente consume el deployment.

### Permisos necesarios
- `Azure AI Developer` (en el proyecto Foundry o en el hub) para invocar el deployment.
- `Cognitive Services OpenAI User` en el recurso de Azure OpenAI subyacente del proyecto.
- Acceso de lectura al Resource Group si necesitas listar información adicional.
El usuario debe iniciar sesión con `az login` antes de ejecutar el script.

## Ejecución
```bash
# Instalar dependencias (desde la raíz del repo)
cd ../../..
pip install -r requirements.txt

# Variables necesarias en .env (generadas también por infra/show-endpoints):
# MAF_ENDPOINT_API=https://<foundry-maf>.services.ai.azure.com
# MAF_DEPLOYMENT_NAME=gpt-4o-mini
# MAF_PROJECT_NAME=maf   # opcional, solo para logging

# Ejecutar el chat
cd platforms/maf/01-simple-chat
python src/main.py
```

## Tests
```bash
pytest tests/
```
