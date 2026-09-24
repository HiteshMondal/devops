"""
env_loader.py
--------------------------------------------------------------------------
Standalone environment loader for the Azure Pulumi stack.

Design goal: this Pulumi program must run correctly on its own —
`cd platform/infra/pulumi && pulumi up` — whether or not it was launched
through run.sh. It must NOT import run.sh, or any other script.
It only depends on the repo's single source of truth for config:
the .env file at the project root (per README: ".env is the SINGLE SOURCE
OF TRUTH for Ports, Variables, and Secrets").

Resolution order (highest priority first):
  1. Variables already present in the process environment (e.g. exported
     by run.sh , or CI/CD secrets) — never overridden.
  2. Values found in a discovered .env file.
  3. Caller-supplied defaults (see get_env() in __main__.py).

.env discovery:
  - Respects an explicit ENV_FILE=/path/to/.env override.
  - Otherwise walks upward from this file's directory looking for a file
    named ".env", stopping at the filesystem root. This means the file can
    be moved anywhere inside the repo and it will still find the project's
    .env without any hard-coded relative path like "../../.env".
"""

from __future__ import annotations

import os
from pathlib import Path

try:
    from dotenv import dotenv_values
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "Missing dependency 'python-dotenv'. Run: pip install -r requirements.txt"
    ) from exc

_ENV_FILENAME = ".env"
_MAX_WALK_LEVELS = 10


def _discover_env_file() -> Path | None:
    explicit = os.environ.get("ENV_FILE")
    if explicit:
        path = Path(explicit).expanduser().resolve()
        return path if path.is_file() else None

    current = Path(__file__).resolve().parent
    for _ in range(_MAX_WALK_LEVELS):
        candidate = current / _ENV_FILENAME
        if candidate.is_file():
            return candidate
        if current.parent == current:  # reached filesystem root
            break
        current = current.parent
    return None


def load_env() -> dict[str, str]:

    env_path = _discover_env_file()
    file_values: dict[str, str] = {}

    if env_path is not None:
        file_values = {k: v for k, v in dotenv_values(env_path).items() if v is not None}
        for key, value in file_values.items():
            os.environ.setdefault(key, value)

    return {
        "env_file_found": str(env_path) if env_path else "",
        **file_values,
    }