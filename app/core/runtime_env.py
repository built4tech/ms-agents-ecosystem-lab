"""Utilidades de entorno de ejecución (local vs cloud)."""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv


def is_cloud_runtime() -> bool:
    return bool(
        os.getenv("WEBSITE_INSTANCE_ID")
        or os.getenv("WEBSITE_SITE_NAME")
        or os.getenv("FUNCTIONS_WORKER_RUNTIME")
    )


def find_env_file(start_path: Path) -> Path | None:
    for parent in [start_path, *start_path.parents]:
        candidate = parent / ".env"
        if candidate.exists():
            return candidate
    return None


def load_local_env_if_needed(start_path: Path) -> Path | None:
    if is_cloud_runtime():
        return None

    env_file = find_env_file(start_path)
    if env_file:
        load_dotenv(env_file)
    return env_file
