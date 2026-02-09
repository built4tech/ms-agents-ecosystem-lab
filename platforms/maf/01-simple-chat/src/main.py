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

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parents[4]


def load_env() -> None:
    """Carga variables desde el .env en la raiz del repo."""
    load_dotenv(PROJECT_ROOT / ".env")


def validate_env_vars() -> tuple[str, str, str]:
    """Valida y retorna las variables de entorno necesarias."""
    endpoint = os.getenv("MAF_ENDPOINT")
    project_name = os.getenv("MAF_PROJECT_NAME")
    deployment = os.getenv("MAF_DEPLOYMENT_NAME")

    if not all([endpoint, project_name, deployment]):
        raise ValueError(
            "Faltan variables en .env: MAF_ENDPOINT, MAF_PROJECT_NAME, MAF_DEPLOYMENT_NAME"
        )

    return endpoint, project_name, deployment


def get_project_client(endpoint: str) -> AIProjectClient:
    """Crea cliente de proyecto AI Foundry."""
    return AIProjectClient(
        endpoint=endpoint,
        credential=DefaultAzureCredential(),
    )


async def chat_loop(openai_client, deployment: str) -> None:
    """Bucle principal de chat interactivo."""
    print("\n" + "=" * 60)
    print(" CHAT INTERACTIVO - Microsoft Agent Framework")
    print("=" * 60)
    print(" Escribe 'exit' o 'salir' para terminar")
    print(" Escribe 'clear' o 'limpiar' para limpiar el historial")
    print("=" * 60 + "\n")

    messages = [
        {
            "role": "system",
            "content": (
                "Eres un asistente util y claro. Responde en espanol a menos "
                "que el usuario escriba en otro idioma."
            ),
        }
    ]

    while True:
        try:
            user_input = input("\n[Tu]: ").strip()
            if not user_input:
                continue

            if user_input.lower() in ["exit", "salir", "quit"]:
                print("\nHasta luego.")
                break

            if user_input.lower() in ["clear", "limpiar"]:
                messages[:] = messages[:1]
                print("\n[Sistema]: Historial limpiado. Nuevo chat iniciado.")
                continue

            messages.append({"role": "user", "content": user_input})

            response = openai_client.chat.completions.create(
                model=deployment,
                messages=messages,
                temperature=0.7,
                max_tokens=800,
            )

            assistant_message = response.choices[0].message.content
            messages.append({"role": "assistant", "content": assistant_message})
            print(f"\n[Asistente]: {assistant_message}")
        except KeyboardInterrupt:
            print("\n\nSesion interrumpida.")
            break
        except Exception as exc:
            print(f"\n[Error]: {exc}")
            if messages and messages[-1].get("role") == "user":
                messages.pop()


def main() -> None:
    """Funcion principal."""
    load_env()
    endpoint, project_name, deployment = validate_env_vars()

    print(f"\n[INFO] Conectando a Hub: {project_name}")
    print(f"[INFO] Endpoint: {endpoint}")
    print(f"[INFO] Deployment: {deployment}\n")

    project_client = get_project_client(endpoint)
    openai_client = project_client.get_openai_client()

    asyncio.run(chat_loop(openai_client, deployment))


if __name__ == "__main__":
    main()
