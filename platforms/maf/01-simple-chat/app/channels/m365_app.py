"""Microsoft 365 channel application using Microsoft 365 Agents SDK."""

import asyncio
from app.core.chat_service import ChatService
from microsoft_agents.hosting.aiohttp import CloudAdapter
from microsoft_agents.hosting.core import AgentApplication, MemoryStorage, TurnContext, TurnState

AGENT_APP = AgentApplication[TurnState](
    storage=MemoryStorage(),
    adapter=CloudAdapter(),
)

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


@AGENT_APP.conversation_update("membersAdded")
async def on_members_added(context: TurnContext, _: TurnState):
    await context.send_activity("Hola, soy tu agente conectado a Foundry. Escribe /help para ayuda.")
    return True


@AGENT_APP.message("/help")
async def on_help(context: TurnContext, _: TurnState):
    await context.send_activity("Comandos: /help, /clear. O escribe una pregunta normal.")


@AGENT_APP.activity("message")
async def on_message(context: TurnContext, _: TurnState):
    await _ensure_started()
    text = (context.activity.text or "").strip()

    if not text:
        await context.send_activity("No recibí texto en el mensaje.")
        return

    if text.lower() in {"exit", "salir", "quit"}:
        await context.send_activity("En este canal no se cierra sesión con 'exit'. Puedes seguir conversando.")
        return

    if text == "/clear":
        response = await chat_service.ask("clear")
        await context.send_activity(response)
        return

    answer = await chat_service.ask(text)
    await context.send_activity(answer)
