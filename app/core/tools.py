"""Herramientas reutilizables para agentes del laboratorio.

Este módulo contiene tools genéricas que pueden ser registradas en cualquier
agente. No debe contener lógica específica de canales.
"""

from __future__ import annotations

import random
from typing import Annotated

from agent_framework import tool, HostedWebSearchTool
from pydantic import Field

ESTADOS_TIEMPO = ["soleado", "nublado", "lluvioso"]
ROUTE_WEATHER_KEYWORDS = ("tiempo", "clima", "meteo", "pronostico")

# NOTA: HostedWebSearchTool no está soportado en Azure OpenAI Chat Completions API
# Requiere Azure AI Foundry Agents Service o configurar Bing Search separadamente
# web_search_tool = HostedWebSearchTool()

# Esta función es un ejemplo de cómo podríamos enrutar a diferentes tools según el mensaje del usuario.
def route_tools_for_message(message: str) -> list[object]:
	"""Devuelve el conjunto de tools segun el texto del usuario."""
	# Solo weather tool disponible actualmente
	return [get_weather_by_city]


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
# Nota: esta tool no usa decorador @tool porque no es una funcion local. Si no que 
# se encuentra en el framework y se registra directamente como instancia.
web_search_tool = HostedWebSearchTool(
    description=(
        "Busca informacion actual en internet para responder preguntas "
        "de actualidad, noticias, tendencias y datos recientes."
    ),
    additional_properties={
        "user_location": {
            "city": "Madrid",
            "country": "ES",
            "timezone": "Europe/Madrid",
        },
        # Ajusta segun soporte real de tu deployment/modelo:
        # "search_context_size": "medium",
    },
)

__all__ = ["get_weather_by_city", "web_search_tool", "route_tools_for_message"]


