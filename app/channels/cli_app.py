"""CLI channel runner for interactive terminal conversations."""

import logging
from app.core.agent_viewer import ChatService

logger = logging.getLogger(__name__)


async def run_cli_channel() -> None:
    """Ejecuta la experiencia de chat interactivo por terminal."""
    chat_service = ChatService()
    await chat_service.start()

    print("\n" + "=" * 60)
    print(" CHAT INTERACTIVO - Microsoft Agent Framework")
    print("=" * 60)
    print(" Escribe 'exit' o 'salir' para terminar")
    print(" Escribe 'clear' o 'limpiar' para limpiar el historial")
    print("=" * 60 + "\n")

    try:
        while True:
            try:
                user_input = input("\n[Tu]: ").strip()

                if not user_input:
                    continue

                if user_input.lower() in ["exit", "salir", "quit"]:
                    print("\n[Asistente]: ¡Adiós! Que tengas un buen día.")
                    break

                response = await chat_service.ask(user_input)
                print(f"\n[Asistente]: {response}")

            except KeyboardInterrupt:
                print("\n\nSesión interrumpida.")
                break
            except Exception as exc:
                logger.error(f"Error inesperado: {exc}", exc_info=True)
                print("\n[Error]: Ocurrió un error inesperado. Intenta de nuevo.")

    finally:
        await chat_service.stop()
