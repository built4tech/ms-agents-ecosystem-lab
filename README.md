
# ms-agents-ecosystem-lab

Laboratorio comparativo de agentes en el ecosistema Microsoft:
- **Microsoft Agent Framework (MAF)**
- **Microsoft Foundry SDK**
- **CrewAI** (con modelos alojados en Azure/OpenAI/Ollama)

## Objetivos
1. Entender implicaciones arquitectónicas de usar Foundry vs MAF vs CrewAI.
2. Medir complejidad, observabilidad, extensibilidad y coste.
3. Proveer ejemplos incrementales: **simple chat**, **Graph-enabled**, **orquestado**.

## Estructura
- `platforms/{foundry|maf|crewai}/{01|02|03}/`
- `shared/` prompts, datasets, evals, utils
- `config/` backends de modelos, Graph, MCP
- `infra/` IaC y devcontainer
- `docs/` comparativas, ADRs, diagramas

## Cómo empezar
1. Clona y copia `.env.example` → `.env`.
2. Elige un proyecto, instala dependencias y ejecuta:
   ```bash
   make setup && make run
