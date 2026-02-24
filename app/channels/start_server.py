"""HTTP server bootstrap for Microsoft 365 channel endpoint."""

from os import environ
from aiohttp.web import Application, Request, Response, run_app
from microsoft_agents.hosting.aiohttp import (
    CloudAdapter,
    jwt_authorization_middleware,
    start_agent_process,
)
from microsoft_agents.hosting.core import AgentApplication, AgentAuthConfiguration


def start_server(
    agent_application: AgentApplication,
    auth_configuration: AgentAuthConfiguration | None,
) -> None:
    """Inicia el servidor HTTP para recibir actividades en /api/messages."""

    async def entry_point(req: Request) -> Response:
        agent: AgentApplication = req.app["agent_app"]
        adapter: CloudAdapter = req.app["adapter"]
        return await start_agent_process(req, agent, adapter)

    app = Application(middlewares=[jwt_authorization_middleware])
    app.router.add_post("/api/messages", entry_point)
    app.router.add_get("/api/messages", lambda _: Response(status=200))
    app["agent_configuration"] = auth_configuration
    app["agent_app"] = agent_application
    app["adapter"] = agent_application.adapter

    run_app(
        app,
        host=environ.get("AGENT_HOST", "0.0.0.0"),
        port=int(environ.get("PORT", "3978")),
    )
