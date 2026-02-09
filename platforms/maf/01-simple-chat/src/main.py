"""
Simple Chat usando Microsoft Agent Framework (MAF)
=================================================

Este script implementa un chat interactivo usando Agent Framework.
Lee el endpoint y el deployment desde el archivo .env en la raiz.

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

from agent_framework.azure import AzureOpenAIChatClient
from azure.identity import AzureCliCredential
from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parents[4]


def load_env() -> None:
    """Carga variables desde el .env en la raiz del repo."""
    load_dotenv(PROJECT_ROOT / ".env")


def ensure_azure_openai_env() -> None:
    """Asegura que las variables esperadas por Agent Framework esten presentes."""
    endpoint = os.getenv("MAF_ENDPOINT") 
    deployment = os.getenv("MAF_DEPLOYMENT_NAME") 

    if not endpoint or not deployment:
        raise ValueError(
            "Falta MAF_ENDPOINT y/o MAF_DEPLOYMENT_NAME en el .env"
        )

    os.environ.setdefault("AZURE_OPENAI_ENDPOINT", endpoint)
    os.environ.setdefault("AZURE_OPENAI_CHAT_DEPLOYMENT_NAME", deployment)


def build_agent():
    """Crea el agente de chat completion con Azure OpenAI."""
    client = AzureOpenAIChatClient(credential=AzureCliCredential())
    return client.as_agent(
        name="SimpleChat",
        instructions=(
            "Eres un asistente util y claro. Responde en espanol a menos "
            "que el usuario escriba en otro idioma."
        ),
    )


async def chat_loop() -> None:
    """Bucle principal de chat interactivo."""
    print("\n" + "=" * 60)
    print(" CHAT INTERACTIVO - Microsoft Agent Framework")
    print("=" * 60)
    print(" Escribe 'exit' o 'salir' para terminar")
    print(" Escribe 'clear' o 'limpiar' para nuevo chat")
    print("=" * 60 + "\n")

    agent = build_agent()

    while True:
        try:
            user_input = input("\n[Tu]: ").strip()
            if not user_input:
                continue

            if user_input.lower() in ["exit", "salir", "quit"]:
                print("\nHasta luego.")
                break

            if user_input.lower() in ["clear", "limpiar"]:
                agent = build_agent()
                print("\n[Sistema]: Historial limpiado. Nuevo chat iniciado.")
                continue

            result = await agent.run(user_input)
            print(f"\n[Asistente]: {result.text}")
        except KeyboardInterrupt:
            print("\n\nSesion interrumpida.")
            break
        except Exception as exc:
            print(f"\n[Error]: {exc}")


def main() -> None:
    """Funcion principal."""
    load_env()
    ensure_azure_openai_env()
    asyncio.run(chat_loop())


if __name__ == "__main__":
    main()
