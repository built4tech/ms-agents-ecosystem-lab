import logging
import os
from pathlib import Path

from app.core.interfaces import AgentInterface
from app.core.runtime_env import is_cloud_runtime, load_local_env_if_needed
from app.core.tools import get_weather_by_city, web_search_tool, route_tools_for_message

from azure.identity import DefaultAzureCredential

from agent_framework_azure_ai import AzureAIClient
from agent_framework import ChatAgent, AgentThread, ChatMessage, Content

# Configuración del logger a nivel INFO para mostrar mensajes informativos durante la ejecución del agente.
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TOOL_LIMIT_HINTS = (
    "max_invocations",
    "max invocations",
    "invocation limit",
    "too many invocations",
)

APPROVAL_YES = {"si", "yes", "approve", "ok", "vale", "confirm"}
APPROVAL_NO = {"no", "cancel", "cancelar", "rechazar"}

# Configurar httpx para no mostrar logs (propagate=False evita que los mensajes suban al logger raíz)
logging.getLogger("httpx").propagate = False

ENV_FILE = load_local_env_if_needed(Path(__file__).resolve())


def _get_azure_credential():
    """Devuelve la credencial Azure apropiada para el entorno actual.
    
    - En cloud: usa DefaultAzureCredential (Managed Identity preferida)
    - En local: usa DefaultAzureCredential que intentará Azure CLI, VS Code, etc.
    """
    if is_cloud_runtime():
        return DefaultAzureCredential(exclude_interactive_browser_credential=True)
    else:
        # En local, DefaultAzureCredential probará múltiples métodos:
        # 1. Environment variables
        # 2. Workload Identity
        # 3. Managed Identity
        # 4. Azure CLI
        # 5. Azure PowerShell
        # 6. Visual Studio Code
        return DefaultAzureCredential(
            exclude_interactive_browser_credential=True,
            exclude_shared_token_cache_credential=True,
        )


class SimpleChatAgent(AgentInterface):
    """Un agente conversacional simple que implementa la interfaz AgentInterface.
    Este agente responde a los mensajes del usuario con respuestas predefinidas
    basadas en el mensaje recibido."""

    # Definición del prompt que se le dará al agente para guiar su comportamiento, se establece como una variable de clase, en vez de como una variable de instancia, 
    # de esta forma es fácilmente modificable y accesible en toda la clase.
    AGENT_PROMPT = (
    "Eres un agente conversacional claro y conciso que puede buscar información en internet."
    " Responde en español a menos que el usuario use otro idioma y prioriza respuestas breves y accionables."
    " Cuando el usuario pregunte sobre temas actuales, noticias o información reciente,"
    " usa la herramienta web_search para obtener información actualizada."
    " Evita usar web_search para consultas muy genéricas o ataques de scraping."
    " En su lugar, realiza búsquedas específicas por tema o área de interés."
    " Siempre proporciona contexto de dónde proviene la información."
    )

    def __init__(self) -> None:
        """Constructor del agente, no requiere parámetros de inicialización."""
        
        # Definición de las variables de instancia para el cliente de chat y el agente, se inicializan como None y se configuran en el método initialize
        self.chat_client: AzureAIClient | None = None
        self.agent: ChatAgent | None = None
        self.agent_thread: AgentThread | None = None
        self._pending_approval: Content | None = None

        # No se llama a initialize en el constructor, ya que es un método asíncrono y no se pueden llamar métodos asíncronos desde el constructor.
        # En vez de ello, llamar a initialize desde el código que instancia el agente,
        # en este caso desde main.py (modo cli) o main_cli.py; esto permite que la inicialización
        # del agente se realice de manera asíncrona y no bloquee la ejecución del programa.

        # self.initialize()


        
    def _create_chat_client(self) -> None:
        """Crea un cliente de chat Azure AI que posteriormente vincularemos con el agente."""
        
        # Obtención de las variables de entorno necesarias para configurar el cliente de chat
        logger.debug("Obteniendo variables de entorno: ENDPOINT_API, DEPLOYMENT_NAME")
        endpoint_api = os.getenv("ENDPOINT_API")
        deployment   = os.getenv("DEPLOYMENT_NAME")
        project_name = os.getenv("PROJECT_NAME")

        # Comprobación de que todas las variables necesarias están presentes, si falta alguna se lanza una excepción
        if not all([endpoint_api, deployment]):
            logger.error("Faltan variables obligatorias: ENDPOINT_API o DEPLOYMENT_NAME")
            raise ValueError("Falta alguna de las variables de entorno necesarias: ENDPOINT_API, DEPLOYMENT_NAME")
        
        credential = _get_azure_credential()
        env_type = "cloud" if is_cloud_runtime() else "local"
        logger.info(f"Usando autenticación Entra ID ({env_type}) con DefaultAzureCredential.")
        
        # Creación del cliente de chat Azure AI con soporte para web search y herramientas avanzadas
        self.chat_client = AzureAIClient(
            project_endpoint=endpoint_api,
            model_deployment_name=deployment,
            credential=credential,
        )
        logger.info("[OK] Cliente Azure AI creado exitosamente con soporte para web search.")
    
    def _create_agent(self) -> None:
        """Asigna el cliente de chat creado al agente para que pueda interactuar con el entorno."""
        logger.debug(f"Creando agente con prompt: {self.AGENT_PROMPT[:50]}...")
        self.agent = ChatAgent(
            chat_client=self.chat_client,
            name="SimpleChatAgent",
            instructions=self.AGENT_PROMPT,
            tools=[get_weather_by_city, web_search_tool],
            )
        logger.info("[OK] Agente creado con web search habilitado.")

    def _initialize_agent_thread(self) -> None:
        """Crea un hilo para ejecutar el agente de manera asíncrona, permitiendo que el agente procese mensajes sin bloquear la ejecución principal."""
        if not self.agent:
            logger.error("No se puede crear el hilo del agente porque el agente no ha sido inicializado.")
            raise ValueError("El agente debe ser inicializado antes de crear el hilo.")
        
        logger.debug("Creando AgentThread...")
        self.agent_thread = self.agent.get_new_thread()
        logger.info("[OK] Hilo del agente iniciado exitosamente.")

    async def initialize(self) -> None:
        """Inicializa el agente cargando las variables de entorno necesarias."""
        if ENV_FILE:
            logger.debug(f"Cargando .env desde {ENV_FILE}")
        self._create_chat_client()
        self._create_agent()
        self._initialize_agent_thread()
        logger.info("[OK] Agente inicializado y listo para interactuar.")

    async def process_user_message(self, message: str) -> str:
        """Procesa el mensaje del usuario y devuelve una respuesta predefinida."""

        logger.debug(f"Procesando mensaje: '{message}'")
        
        # Respuestas simples basadas en palabras clave en el mensaje del usuario
        if message.lower() in ["exit", "salir", "quit", "adios"]:
            logger.debug("Comando de salida detectado.")
            response = "¡Adiós! Que tengas un buen día."
        elif self._pending_approval is not None:
            normalized = message.strip().lower()
            if normalized in APPROVAL_YES:
                logger.debug("Aprobacion recibida para tool pendiente.")
                approval_response = self._pending_approval.to_function_approval_response(approved=True)
                self._pending_approval = None
                approval_message = ChatMessage(role="user", contents=[approval_response])
                response = await self.agent.run([approval_message], thread=self.agent_thread)
            elif normalized in APPROVAL_NO:
                logger.debug("Aprobacion rechazada para tool pendiente.")
                self._pending_approval = None
                response = "Entendido, no ejecutare la herramienta."
            else:
                response = "Necesito una confirmacion: responde 'si' para aprobar o 'no' para cancelar."
        elif message.lower() in ["clear", "limpiar"]:
            logger.debug("Comando de limpieza detectado, reiniciando hilo.")
            # Reinicia el hilo del agente para limpiar el historial de conversación y comenzar un nuevo chat
            self._initialize_agent_thread()
            response = "Historial limpiado. Nuevo chat iniciado."
        elif "hola" in message.lower():
            logger.debug("Saludo detectado, respondiendo con respuesta predefinida.")
            response = "¡Hola! ¿En qué puedo ayudarte hoy?"
        else:
            # Para cualquier otro mensaje, se envía el mensaje al agente para que genere una respuesta 
            # utilizando el LLM configurado.
            try:
                logger.debug(f"Enviando mensaje al agente: {message}")
                tools_for_call = route_tools_for_message(message)
                logger.info(f"[TOOLS_CALL] Pasadas a agent.run(): {[t.name if hasattr(t, 'name') else type(t).__name__ for t in tools_for_call]}")
                response = await self.agent.run(message, thread=self.agent_thread, tools=tools_for_call)
                logger.debug("Respuesta generada por el agente.")
            except Exception as e:
                logger.error(f"Error al procesar el mensaje: {e}", exc_info=True)
                error_text = str(e).lower()
                if any(hint in error_text for hint in TOOL_LIMIT_HINTS):
                    response = (
                        "Se alcanzó el límite de uso de una herramienta en esta conversación. "
                        "Puedes escribir 'clear' para reiniciar el chat e intentarlo de nuevo."
                    )
                else:
                    response = "Lo siento, ocurrió un error al procesar tu mensaje."

        logger.debug(f"Usuario: {message}")
        response_text = response.text if hasattr(response, 'text') else str(response)
        if not response_text and hasattr(response, "messages"):
            pending_request = None
            for msg in response.messages:
                for content in msg.contents:
                    if getattr(content, "type", None) == "function_approval_request":
                        pending_request = content
                        break
                if pending_request is not None:
                    break
            if pending_request is not None:
                self._pending_approval = pending_request
                tool_name = pending_request.function_call.name if hasattr(pending_request, "function_call") else None
                response_text = (
                    f"Necesito tu aprobacion para ejecutar la herramienta"
                    f"{f' {tool_name}' if tool_name else ''}. Responde 'si' para aprobar o 'no' para cancelar."
                )
        logger.debug(f"Asistente: {response_text}")

        return response_text

    async def cleanup(self) -> None:
        """Limpia cualquier recurso utilizado por el agente (no es necesario en este caso pero se implementa para mantener la consistencia).
        Si el agente tuviera recursos como conexiones abiertas, archivos temporales, etc., aquí es donde se cerrarían o eliminarían."""
        logger.debug("Iniciando limpieza de recursos...")
        logger.info("[OK] Agente limpiado y recursos liberados.")
