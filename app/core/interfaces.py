from abc import ABC, abstractmethod

class AgentInterface(ABC):
    """Interface for the agent to interact with the environment.
    it implements three methods:
    - initialize: to initialize the agent with the necessary information to interact with the environment.
    - process_user_message: to process the user message and return a response.
    - cleanup: to clean up any resources used by the agent."""

    @abstractmethod
    def initialize(self) -> None:
        """Initialize the agent with the necessary information to interact with the environment."""
        pass

    @abstractmethod
    def process_user_message(self, message: str) -> str:
        """Process the user message and return a response."""
        pass

    @abstractmethod
    def cleanup(self) -> None:
        """Clean up any resources used by the agent."""
        pass

def check_agent_interface(agent: object) -> bool:
    """Check if the agent implements the AgentInterface."""
    return isinstance(agent, AgentInterface)
