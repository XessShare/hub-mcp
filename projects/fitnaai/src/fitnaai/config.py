"""fitnaai configuration via environment variables."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment or .env file."""

    app_name: str = "fitnaai"
    debug: bool = False

    # API server
    host: str = "0.0.0.0"
    port: int = 8000

    # Ollama backend (runs on Host 2 / pve-ryzen)
    ollama_base_url: str = "http://192.168.16.3:11434"
    ollama_model: str = "llama3.2"

    # Data paths
    data_dir: str = "/data"

    model_config = {"env_prefix": "FITNAAI_", "env_file": ".env"}


settings = Settings()
