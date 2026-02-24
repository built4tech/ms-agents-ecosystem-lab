"""Helpers de autenticación para runtime M365 en Fase 3.

Este módulo separa dos responsabilidades:

- Autenticación entrante (inbound): validación de tokens JWT que llegan al bot.
    Se representa con ``AgentAuthConfiguration`` y la usa el pipeline HTTP.
- Autenticación saliente (outbound): obtención/renovación de tokens OAuth para
    llamar servicios externos. La gestiona ``MsalConnectionManager``.

`CONNECTIONS` define conexiones reales (credenciales).
`CONNECTIONSMAP` define reglas para seleccionar qué conexión usar según
``AUDIENCE`` y/o ``SERVICEURL``.
"""

import os
from pathlib import Path

from microsoft_agents.authentication.msal import MsalConnectionManager
from microsoft_agents.hosting.aiohttp import CloudAdapter
from microsoft_agents.hosting.core import AgentAuthConfiguration
from app.core.runtime_env import load_local_env_if_needed

ENV_FILE = load_local_env_if_needed(Path(__file__).resolve())


def _require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise ValueError(f"Falta variable de entorno requerida para Fase 3: {name}")
    return value


def create_m365_auth_runtime() -> tuple[CloudAdapter, AgentAuthConfiguration]:
    """Construye adapter y configuración auth de canal M365 desde variables de entorno.

    Implementación actual:
    - Una única conexión real: ``SERVICE_CONNECTION``.
    - ``CONNECTIONSMAP`` vacío, por lo que el runtime usa la conexión por defecto
      para todos los casos.

    Variante 1 (misma conexión para todo, incluido Graph):

    .. code-block:: python

        MsalConnectionManager(
            CONNECTIONS={
                "SERVICE_CONNECTION": {"SETTINGS": {...}},
            },
            CONNECTIONSMAP=[],
        )

    Variante 2 (segunda conexión dedicada a Graph):

    .. code-block:: python

        MsalConnectionManager(
            CONNECTIONS={
                "SERVICE_CONNECTION": {"SETTINGS": {...}},
                "GRAPH_CONNECTION": {"SETTINGS": {...}},
            },
            CONNECTIONSMAP=[
                {"AUDIENCE": "", "SERVICEURL": "*", "CONNECTION": "SERVICE_CONNECTION"},
                {
                    "AUDIENCE": "",
                    "SERVICEURL": r"^https://graph\\.microsoft\\.com/.*$",
                    "CONNECTION": "GRAPH_CONNECTION",
                },
            ],
        )
    """
    client_id = _require_env("MICROSOFT_APP_ID")
    client_secret = _require_env("MICROSOFT_APP_PASSWORD")
    tenant_id = _require_env("MICROSOFT_APP_TENANTID")

    auth_configuration = AgentAuthConfiguration(
        client_id=client_id,
        client_secret=client_secret,
        tenant_id=tenant_id,
    )

    connection_manager = MsalConnectionManager(
        CONNECTIONS={
            "SERVICE_CONNECTION": {
                "SETTINGS": {
                    "CLIENTID": client_id,
                    "CLIENTSECRET": client_secret,
                    "TENANTID": tenant_id,
                }
            }
        },
        CONNECTIONSMAP=[],
    )

    adapter = CloudAdapter(connection_manager=connection_manager)
    return adapter, auth_configuration
