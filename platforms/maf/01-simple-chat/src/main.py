"""
Simple Chat usando Microsoft Agent Framework (MAF) via Azure AI Foundry
========================================================================

Este script implementa un chat interactivo usando AIProjectClient.
Toma el endpoint del Hub de Azure AI Foundry desde el .env para trazabilidad
completa, Content Safety y otros controles de seguridad.

Uso:
    python main.py

Comandos:
    - Escribe tu mensaje y presiona Enter para chatear
    - Escribe 'exit' o 'salir' para terminar la sesion
    - Escribe 'clear' o 'limpiar' para limpiar el historial
"""

import asyncio
import os
from pathlib import Path

from agent_framework import AgentThread, ChatAgent
from agent_framework.azure import AzureOpenAIChatClient
from azure.identity import AzureCliCredential
from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parents[4]
AGENT_PROMPT = (
    "Eres un agente conversacional claro y conciso."
    " Responde en espanol a menos que el usuario use otro idioma"
    " y prioriza respuestas breves y accionables."
)


def load_env() -> None:
    """Carga variables desde el .env en la raiz del repo."""
    load_dotenv(PROJECT_ROOT / ".env")


def validate_env_vars() -> dict[str, str | None]:
    """Valida variables requeridas y opcionales para Azure OpenAI."""
    endpoint = os.getenv("ENDPOINT_API")
    deployment = os.getenv("DEPLOYMENT_NAME")
    project_name = os.getenv("PROJECT_NAME")
    api_version = os.getenv("API_VERSION")
    api_key = os.getenv("API_KEY")

    missing = [
        name
        for name, val in {
            "ENDPOINT_API": endpoint,
            "DEPLOYMENT_NAME": deployment,
            "PROJECT_NAME": project_name,
            "API_VERSION": api_version,
        }.items()
        if not val
    ]
    if missing:
        raise ValueError(f"Faltan variables en .env: {', '.join(missing)}")

    return {
        "endpoint": endpoint,
        "deployment": deployment,
        "project_name": project_name,
        "api_version": api_version,
        "api_key": api_key,
    }


def create_chat_client(config: dict[str, str | None]) -> AzureOpenAIChatClient:
    """Crea el cliente de chat usando API key (si existe) o Azure CLI."""
    auth_kwargs: dict[str, object]
    if config["api_key"]:
        auth_kwargs = {"api_key": config["api_key"]}
        print("[INFO] Autenticacion: API key")
    else:
        auth_kwargs = {"credential": AzureCliCredential()}
        print("[INFO] Autenticacion: Azure CLI")

    return AzureOpenAIChatClient(
        endpoint=config["endpoint"],
        deployment_name=config["deployment"],
        api_version=config["api_version"],
        **auth_kwargs,
    )


def create_agent(chat_client: AzureOpenAIChatClient) -> ChatAgent:
    """Crea el agente de MAF con instrucciones base."""
    return ChatAgent(chat_client=chat_client, instructions=AGENT_PROMPT, tools=[])


async def chat_loop(agent: ChatAgent) -> None:
    """Bucle principal de chat interactivo."""
    print("\n" + "=" * 60)
    print(" CHAT INTERACTIVO - Microsoft Agent Framework")
    print("=" * 60)
    print(" Escribe 'exit' o 'salir' para terminar")
    print(" Escribe 'clear' o 'limpiar' para limpiar el historial")
    print("=" * 60 + "\n")

    thread = AgentThread()

    while True:
        try:
            user_input = input("\n[Tu]: ").strip()
            if not user_input:
                continue

            if user_input.lower() in ["exit", "salir", "quit"]:
                print("\nHasta luego.")
                break

            if user_input.lower() in ["clear", "limpiar"]:
                thread = AgentThread()
                print("\n[Sistema]: Historial limpiado. Nuevo chat iniciado.")
                continue

            response = await agent.run(user_input, thread=thread)
            print(f"\n[Asistente]: {response.text}")
        except KeyboardInterrupt:
            print("\n\nSesion interrumpida.")
            break
        except Exception as exc:
            print(f"\n[Error]: {exc}")


def main() -> None:
    """Funcion principal."""
    load_env()

    config = validate_env_vars()
    endpoint = config["endpoint"]
    project_name = config["project_name"]
    deployment = config["deployment"]

    print(f"\n[INFO] Conectando a Proyecto: {project_name}")
    print(f"[INFO] Endpoint: {endpoint}")
    print(f"[INFO] Deployment: {deployment}\n")

    chat_client = create_chat_client(config)
    agent = create_agent(chat_client)

    asyncio.run(chat_loop(agent))


if __name__ == "__main__":
    main()
