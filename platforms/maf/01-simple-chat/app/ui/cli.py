"""CLI module - Interactive chat interface."""
from app.channels import run_cli_channel



async def run_interactive_chat() -> None:
    """Ejecuta la interfaz de chat interactivo en terminal."""
    await run_cli_channel()
