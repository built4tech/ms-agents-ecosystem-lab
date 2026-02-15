"""Main entry point for MAF Simple Chat application."""
import asyncio
from app.ui import run_interactive_chat


if __name__ == "__main__":
    asyncio.run(run_interactive_chat())
