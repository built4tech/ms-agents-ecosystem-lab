import logging
import os
from pathlib import Path

from app.core.interfaces import AgentInterface
from app.core.runtime_env import is_cloud_runtime, load_local_env_if_needed

from azure.identity import AzureCliCredential, DefaultAzureCredential

from agent_framework.azure import AzureOpenAIChatClient
from agent_framework import ChatAgent, AgentThread

# Configuración del logger a nivel INFO para mostrar mensajes informativos durante la ejecución del agente.
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configurar httpx para no mostrar logs (propagate=False evita que los mensajes suban al logger raíz)
logging.getLogger("httpx").propagate = False

ENV_FILE = load_local_env_if_needed(Path(__file__).resolve())


class SimpleChatAgent(AgentInterface):
    """Un agente conversacional simple que implementa la interfaz AgentInterface.
    Este agente responde a los mensajes del usuario con respuestas predefinidas
    basadas en el mensaje recibido."""

    # Definición del prompt que se le dará al agente para guiar su comportamiento, se establece como una variable de clase, en vez de como una variable de instancia, 
    # de esta forma es fácilmente modificable y accesible en toda la clase.
    AGENT_PROMPT = (
    "Eres un agente conversacional claro y conciso."
    " Responde en espanol a menos que el usuario use otro idioma"
    " y prioriza respuestas breves y accionables."
    )

    def __init__(self) -> None:
        """Constructor del agente, no requiere parámetros de inicialización."""
        
        # Definición de las variables de instancia para el cliente de chat y el agente, se inicializan como None y se configuran en el método initialize
        self.chat_client: AzureOpenAIChatClient | None = None
        self.agent: ChatAgent | None = None
        self.agent_thread: AgentThread | None = None

        # No se llama a initialize en el constructor, ya que es un método asíncrono y no se pueden llamar métodos asíncronos desde el constructor.
        # En vez de ello, llamar a initialize desde el código que instancia el agente,
        # en este caso desde main.py (modo cli) o main_cli.py; esto permite que la inicialización
        # del agente se realice de manera asíncrona y no bloquee la ejecución del programa.

        # self.initialize()


        
    def _create_chat_client(self) -> None:
        """Crea un cliente de chat que posteriormente vincularemos con el agente."""
        
        # Obtención de las variables de entorno necesarias para configurar el cliente de chat
        logger.debug("Obteniendo variables de entorno: ENDPOINT_OPENAI/ENDPOINT_API, DEPLOYMENT_NAME, API_VERSION")
        endpoint     = os.getenv("ENDPOINT_OPENAI") or os.getenv("ENDPOINT_API")
        deployment   = os.getenv("DEPLOYMENT_NAME")
        api_version  = os.getenv("API_VERSION")
        token_scope  = os.getenv("AZURE_OPENAI_TOKEN_ENDPOINT") or "https://cognitiveservices.azure.com/.default"

        # Comprobación de que todas las variables necesarias están presentes, si falta alguna se lanza una excepción
        if not all([endpoint, deployment, api_version]):
            logger.error("Faltan variables obligatorias: ENDPOINT_OPENAI/ENDPOINT_API, DEPLOYMENT_NAME o API_VERSION")
            raise ValueError("Falta alguna de las variables de entorno necesarias: ENDPOINT_OPENAI/ENDPOINT_API, DEPLOYMENT_NAME, API_VERSION")
        
        if is_cloud_runtime():
            credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
            logger.debug("Usando autenticación Entra ID en cloud con DefaultAzureCredential.")
        else:
            credential = AzureCliCredential()
            logger.debug("Usando autenticación Entra ID local con AzureCliCredential.")
        
        # Creación del cliente de chat utilizando las variables de entorno y la autenticación configurada
        self.chat_client = AzureOpenAIChatClient(
            endpoint=endpoint,
            credential=credential,
            token_endpoint=token_scope,
            deployment_name=deployment,
            api_version=api_version,            
        )
        logger.info("✅ Cliente de chat creado exitosamente.")
    
    def _create_agent(self) -> None:
        """Asigna el cliente de chat creado al agente para que pueda interactuar con el entorno."""
        logger.debug(f"Creando agente con prompt: {self.AGENT_PROMPT[:50]}...")
        self.agent = ChatAgent(
            chat_client=self.chat_client,
            instructions=self.AGENT_PROMPT,
            tools=[],
            )
        logger.info("✅ Agente creado y vinculado al cliente de chat.")

    def _initialize_agent_thread(self) -> None:
        """Crea un hilo para ejecutar el agente de manera asíncrona, permitiendo que el agente procese mensajes sin bloquear la ejecución principal."""
        if not self.agent:
            logger.error("No se puede crear el hilo del agente porque el agente no ha sido inicializado.")
            raise ValueError("El agente debe ser inicializado antes de crear el hilo.")
        
        logger.debug("Creando AgentThread...")
        self.agent_thread = self.agent.get_new_thread()
        logger.info("✅ Hilo del agente iniciado exitosamente.")

    async def initialize(self) -> None:
        """Inicializa el agente cargando las variables de entorno necesarias."""
        if ENV_FILE:
            logger.debug(f"Cargando .env desde {ENV_FILE}")
        self._create_chat_client()
        self._create_agent()
        self._initialize_agent_thread()
        logger.info("✅ Agente inicializado y listo para interactuar.")

    async def process_user_message(self, message: str) -> str:
        """Procesa el mensaje del usuario y devuelve una respuesta predefinida."""

        logger.debug(f"Procesando mensaje: '{message}'")
        
        # Respuestas simples basadas en palabras clave en el mensaje del usuario
        if message.lower() in ["exit", "salir", "quit", "adios"]:
            logger.debug("Comando de salida detectado.")
            response = "¡Adiós! Que tengas un buen día."
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
                response = await self.agent.run(message, thread=self.agent_thread)
                logger.debug("Respuesta generada por el agente.")
            except Exception as e:
                logger.error(f"Error al procesar el mensaje: {e}", exc_info=True)
                response = "Lo siento, ocurrió un error al procesar tu mensaje."

        logger.debug(f"Usuario: {message}")
        response_text = response.text if hasattr(response, 'text') else str(response)
        logger.debug(f"Asistente: {response_text}")

        return response_text

    async def cleanup(self) -> None:
        """Limpia cualquier recurso utilizado por el agente (no es necesario en este caso pero se implementa para mantener la consistencia).
        Si el agente tuviera recursos como conexiones abiertas, archivos temporales, etc., aquí es donde se cerrarían o eliminarían."""
        logger.debug("Iniciando limpieza de recursos...")
        logger.info("✅ Agente limpiado y recursos liberados.")
