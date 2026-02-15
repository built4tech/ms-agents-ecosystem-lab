"""CLI module - Interactive chat interface."""
import asyncio
import logging
from app.core import SimpleChatAgent

logger = logging.getLogger(__name__)


async def chat_loop(agent: SimpleChatAgent) -> None:
    """Bucle principal de chat interactivo."""

    while True:
        try:
            user_input = input("\n[Usuario]: ").strip()
            if not user_input:
                continue
            
            respuesta = await agent.process_user_message(user_input)
            print(f"\n[Asistente]: {respuesta}")

        except KeyboardInterrupt:
            await agent.cleanup()
            print("\n\nSesión interrumpida. Hasta luego.")
            break
        
        except Exception as exc:
            print(f"\n[Error]: {exc}")


async def run_interactive_chat() -> None:
    """Ejecuta la interfaz de chat interactivo con el agente."""
    agent = SimpleChatAgent()
    await agent.initialize()
    
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
                
                # Chequea comandos de salida antes de procesar
                if user_input.lower() in ["exit", "salir", "quit"]:
                    print("\n[Asistente]: ¡Adiós! Que tengas un buen día.")
                    break
                
                # process_user_message ya registra los logs internos
                response = await agent.process_user_message(user_input)
                print(f"\n[Asistente]: {response}")
                
            except KeyboardInterrupt:
                print("\n\nSesión interrumpida.")
                break
            except Exception as exc:
                logger.error(f"Error inesperado: {exc}", exc_info=True)
                print(f"\n[Error]: Ocurrió un error inesperado. Intenta de nuevo.")
    
    finally:
        await agent.cleanup()
