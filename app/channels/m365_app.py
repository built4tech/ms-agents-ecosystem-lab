"""Microsoft 365 channel application using Microsoft 365 Agents SDK."""

import asyncio
from app.core.agent_viewer import ChatService
from microsoft_agents.hosting.aiohttp import CloudAdapter
from microsoft_agents.hosting.core import AgentApplication, MemoryStorage, TurnContext, TurnState

chat_service = ChatService()
_is_started = False
_startup_lock = asyncio.Lock()


async def _ensure_started() -> None:
    global _is_started
    if _is_started:
        return

    async with _startup_lock:
        if _is_started:
            return
        await chat_service.start()
        _is_started = True


def create_agent_application(adapter: CloudAdapter | None = None) -> AgentApplication[TurnState]:
    """Crea la aplicación de canal M365 usando un adapter configurable."""
    agent_app = AgentApplication[TurnState](
        storage=MemoryStorage(),
        adapter=adapter or CloudAdapter(),
    )

    @agent_app.conversation_update("membersAdded")
    async def on_members_added(context: TurnContext, _: TurnState):
        await context.send_activity(
            "Hola, soy tu agente conectado a Foundry. Escribe /help para ayuda."
        )
        return True

    @agent_app.message("/help")
    async def on_help(context: TurnContext, _: TurnState):
        await context.send_activity("Comandos: /help, /clear. O escribe una pregunta normal.")

    @agent_app.activity("message")
    async def on_message(context: TurnContext, _: TurnState):
        await _ensure_started()
        text = (context.activity.text or "").strip()

        if not text:
            await context.send_activity("No recibí texto en el mensaje.")
            return

        if text.lower() in {"exit", "salir", "quit"}:
            await context.send_activity(
                "En este canal no se cierra sesión con 'exit'. Puedes seguir conversando."
            )
            return

        if text == "/clear":
            response = await chat_service.ask("clear")
            await context.send_activity(response)
            return

        answer = await chat_service.ask(text)
        await context.send_activity(answer)

    return agent_app


AGENT_APP = create_agent_application()
