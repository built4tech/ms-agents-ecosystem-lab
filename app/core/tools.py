"""Herramientas reutilizables para agentes del laboratorio.

Este módulo contiene tools genéricas que pueden ser registradas en cualquier
agente. No debe contener lógica específica de canales.
"""

from __future__ import annotations

import os
import random
from typing import Annotated

from dotenv import load_dotenv
from agent_framework import tool, HostedWebSearchTool
from pydantic import Field

# Cargar variables de entorno
load_dotenv()

ESTADOS_TIEMPO = ["soleado", "nublado", "lluvioso"]
ROUTE_WEATHER_KEYWORDS = ("tiempo", "clima", "meteo", "pronostico")

# Esta función es un ejemplo de cómo podríamos enrutar a diferentes tools según el mensaje del usuario.
def route_tools_for_message(message: str) -> list[object]:
	"""Devuelve el conjunto de tools segun el texto del usuario."""
	import logging
	logger = logging.getLogger(__name__)
	normalized = message.lower()
	if any(keyword in normalized for keyword in ROUTE_WEATHER_KEYWORDS):
		tools = [get_weather_by_city]
		logger.info("[ROUTE] Detectada palabra clave de tiempo - solo weather_tool")
	else:
		tools = [get_weather_by_city, web_search_tool]
		logger.info("[ROUTE] Sin palabras clave de tiempo - weather_tool + web_search_tool habilitados")
	logger.debug(f"[TOOLS] Habilitadas: {[t.name if hasattr(t, 'name') else str(t) for t in tools]}")
	return tools


@tool(
	name="obtener_tiempo_por_ciudad",
	description=(
		"Devuelve un estado del tiempo simulado para una ciudad. "
		"El resultado se calcula usando un valor aleatorio y puede ser: "
		"soleado, nublado o lluvioso."
	),
	approval_mode="always_require",
	max_invocations=5,
)
def get_weather_by_city(
	ciudad: Annotated[
		str,
		Field(
			description="Ciudad para consultar el tiempo simulado. Ejemplos: Madrid, Bogota, Lima.",
			min_length=1,
		),
	],
) -> str:
	"""Obtiene un tiempo simulado para la ciudad indicada."""
	valor_aleatorio = random.random()
	indice_estado = min(int(valor_aleatorio * len(ESTADOS_TIEMPO)), len(ESTADOS_TIEMPO) - 1)
	estado = ESTADOS_TIEMPO[indice_estado]
	return f"Tiempo para {ciudad}: {estado}. (valor_aleatorio={valor_aleatorio:.3f})"




# Tool hosted del framework para busqueda en internet.
# Ahora soportado nativo con AzureAIClient que se conecta a Azure AI Foundry.
# Nota: esta tool no usa decorador @tool porque no es una funcion local. 
# Se encuentra en el framework y se registra directamente como instancia.
bing_connection_id = os.getenv("BING_CONNECTION_ID")
bing_search_api_key = os.getenv("BING_SEARCH_API_KEY")

web_search_tool = HostedWebSearchTool(
    description=(
        "Busca informacion actual en internet para responder preguntas "
        "de actualidad, noticias, tendencias y datos recientes."
    ),
    connection_id=bing_connection_id,  # Pasar explícitamente el connection ID
    additional_properties={
        "user_location": {
            "city": "Madrid",
            "country": "ES",
            "timezone": "Europe/Madrid",
        },
        # Si el framework requiere la API key también:
        "api_key": bing_search_api_key if bing_search_api_key else None,
    },
)

__all__ = ["get_weather_by_city", "web_search_tool", "route_tools_for_message"]


