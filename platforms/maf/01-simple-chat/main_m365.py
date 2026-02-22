"""Entry point for Microsoft 365 channel endpoint."""

from app.channels.m365_app import AGENT_APP
from app.channels.start_server import start_server


if __name__ == "__main__":
    start_server(AGENT_APP, None)
