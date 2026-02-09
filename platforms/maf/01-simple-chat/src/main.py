"""
Simple Chat Agent usando Microsoft Agent Framework (MAF)
=========================================================

Este script implementa un agente de chat interactivo usando Azure AI Projects SDK.
El agente utiliza el modelo gpt-4o-mini desplegado en Azure OpenAI a través de
la conexión configurada en el AI Foundry Hub.

Uso:
    python main.py

Comandos:
    - Escribe tu mensaje y presiona Enter para chatear
    - Escribe 'exit' o 'salir' para terminar la sesión
    - Escribe 'clear' o 'limpiar' para limpiar el historial
"""

import os
import sys
from pathlib import Path

# Cargar .env desde la raíz del proyecto
project_root = Path(__file__).parent.parent.parent.parent.parent
sys.path.insert(0, str(project_root))

from dotenv import load_dotenv
load_dotenv(project_root / ".env")

from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import AgentThread, MessageRole


def get_project_client() -> AIProjectClient:
    """
    Crea y retorna un cliente de AI Project usando DefaultAzureCredential.
    """
    endpoint = os.getenv("MAF_ENDPOINT", "https://project-maf-agents.services.ai.azure.com")
    
    print(f"Conectando a: {endpoint}")
    
    client = AIProjectClient(
        credential=DefaultAzureCredential(),
        endpoint=endpoint
    )
    
    return client


def create_agent(client: AIProjectClient, model: str = "gpt-4o-mini"):
    """
    Crea un agente de chat con el modelo especificado.
    """
    agent = client.agents.create_agent(
        model=model,
        name="chat-assistant",
        instructions="""Eres un asistente de chat amigable y útil. 
        Responde en español a menos que el usuario te escriba en otro idioma.
        Sé conciso pero informativo en tus respuestas."""
    )
    
    print(f"Agente creado: {agent.id}")
    return agent


def chat_loop(client: AIProjectClient, agent, thread: AgentThread):
    """
    Bucle principal de chat interactivo.
    """
    print("\n" + "="*60)
    print(" CHAT INTERACTIVO - Microsoft Agent Framework")
    print("="*60)
    print(" Escribe 'exit' o 'salir' para terminar")
    print(" Escribe 'clear' o 'limpiar' para nuevo chat")
    print("="*60 + "\n")
    
    while True:
        try:
            # Obtener input del usuario
            user_input = input("\n[Tú]: ").strip()
            
            # Comandos especiales
            if not user_input:
                continue
            
            if user_input.lower() in ['exit', 'salir', 'quit']:
                print("\n¡Hasta luego!")
                break
            
            if user_input.lower() in ['clear', 'limpiar']:
                # Crear nuevo thread para limpiar historial
                thread = client.agents.threads.create()
                print("\n[Sistema]: Historial limpiado. Nuevo chat iniciado.")
                continue
            
            # Enviar mensaje al agente
            client.agents.messages.create(
                thread_id=thread.id,
                role=MessageRole.USER,
                content=user_input
            )
            
            # Ejecutar el agente y esperar respuesta
            run = client.agents.runs.create_and_process(
                thread_id=thread.id,
                agent_id=agent.id
            )
            
            # Verificar el estado del run
            if run.status == "failed":
                print(f"\n[Error]: {run.last_error}")
                continue
            
            # Obtener los mensajes del thread
            messages = client.agents.messages.list(thread_id=thread.id)
            
            # Encontrar la última respuesta del asistente
            for message in messages:
                if message.role == MessageRole.AGENT:
                    # Obtener el contenido del mensaje
                    for content_part in message.content:
                        if hasattr(content_part, 'text'):
                            print(f"\n[Asistente]: {content_part.text.value}")
                    break
                    
        except KeyboardInterrupt:
            print("\n\n¡Sesión interrumpida!")
            break
        except Exception as e:
            print(f"\n[Error]: {str(e)}")
            continue


def cleanup(client: AIProjectClient, agent, thread: AgentThread):
    """
    Limpia los recursos creados (agente y thread).
    """
    try:
        print("\nLimpiando recursos...")
        client.agents.threads.delete(thread.id)
        client.agents.delete(agent.id)
        print("Recursos limpiados correctamente.")
    except Exception as e:
        print(f"Error al limpiar recursos: {e}")


def main():
    """
    Función principal.
    """
    print("\n" + "="*60)
    print(" Iniciando Simple Chat Agent (MAF)")
    print("="*60)
    
    client = None
    agent = None
    thread = None
    
    try:
        # Crear cliente
        client = get_project_client()
        
        # Crear agente
        model = os.getenv("MAF_DEPLOYMENT_NAME", "gpt-4o-mini")
        agent = create_agent(client, model)
        
        # Crear thread para la conversación
        thread = client.agents.threads.create()
        print(f"Thread creado: {thread.id}")
        
        # Iniciar bucle de chat
        chat_loop(client, agent, thread)
        
    except Exception as e:
        print(f"\nError fatal: {e}")
        sys.exit(1)
    finally:
        # Limpiar recursos al salir
        if client and agent and thread:
            cleanup(client, agent, thread)


if __name__ == "__main__":
    main()
