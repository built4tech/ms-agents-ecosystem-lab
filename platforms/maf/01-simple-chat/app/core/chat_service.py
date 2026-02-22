"""Application service layer for chat interactions."""

from app.core.agent import SimpleChatAgent


class ChatService:
    """Servicio de aplicación que encapsula el ciclo de vida del agente de chat."""

    def __init__(self) -> None:
        self._agent = SimpleChatAgent()

    async def start(self) -> None:
        """Inicializa recursos del agente."""
        await self._agent.initialize()

    async def ask(self, user_text: str) -> str:
        """Procesa un mensaje de usuario y devuelve la respuesta."""
        return await self._agent.process_user_message(user_text)

    async def stop(self) -> None:
        """Libera recursos del agente."""
        await self._agent.cleanup()
