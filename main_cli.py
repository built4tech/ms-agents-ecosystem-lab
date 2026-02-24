"""CLI entry point for the simple chat application."""

import asyncio

from app.channels.cli_app import run_cli_channel


if __name__ == "__main__":
    asyncio.run(run_cli_channel())