"""Entry point for Microsoft 365 channel endpoint."""

from app.channels.m365_app import create_agent_application
from app.channels.m365_auth import create_m365_auth_runtime
from app.channels.start_server import start_server


if __name__ == "__main__":
    adapter, auth_configuration = create_m365_auth_runtime()
    agent_app = create_agent_application(adapter=adapter)
    start_server(agent_app, auth_configuration)
