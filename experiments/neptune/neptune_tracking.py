"""
experiments/neptune/neptune_tracking.py
Neptune.ai experiment tracking helper.

Usage:
    from experiments.neptune.neptune_tracking import start_run, log_metrics, log_params, end_run

Prerequisites:
    pip install neptune
    Set NEPTUNE_API_TOKEN and NEPTUNE_PROJECT in .env
"""

import os
import json
from typing import Any

# neptune is optional — fail gracefully so the rest of the project works without it
try:
    import neptune
    NEPTUNE_AVAILABLE = True
except ImportError:
    NEPTUNE_AVAILABLE = False

_run = None  # module-level active run


def start_run(name: str = "default-run", tags: list[str] | None = None) -> Any:
    """
    Initialise a Neptune run.
    Falls back to a no-op dict when Neptune is not installed or credentials are missing.
    """
    global _run

    api_token = os.getenv("NEPTUNE_API_TOKEN", "")
    project   = os.getenv("NEPTUNE_PROJECT", "")

    if not NEPTUNE_AVAILABLE:
        print("[neptune] neptune package not installed — tracking disabled")
        _run = {}
        return _run

    if not api_token or not project:
        print("[neptune] NEPTUNE_API_TOKEN or NEPTUNE_PROJECT not set — tracking disabled")
        _run = {}
        return _run

    _run = neptune.init_run(
        project=project,
        api_token=api_token,
        name=name,
        tags=tags or [],
    )
    print(f"[neptune] Run started: {name}")
    return _run


def log_params(params: dict) -> None:
    """Log a flat or nested dict of hyperparameters."""
    if not _run or not NEPTUNE_AVAILABLE or isinstance(_run, dict):
        print(f"[neptune] params (no-op): {params}")
        return
    _run["parameters"] = params


def log_metrics(metrics: dict, step: int | None = None) -> None:
    """Log a dict of metric name → value, with optional step."""
    if not _run or not NEPTUNE_AVAILABLE or isinstance(_run, dict):
        print(f"[neptune] metrics (no-op): {metrics}")
        return
    for key, value in metrics.items():
        if step is not None:
            _run[f"metrics/{key}"].append(value, step=step)
        else:
            _run[f"metrics/{key}"] = value


def log_artifact(path: str, destination: str | None = None) -> None:
    """Upload a local file as a Neptune artifact."""
    if not _run or not NEPTUNE_AVAILABLE or isinstance(_run, dict):
        print(f"[neptune] artifact (no-op): {path}")
        return
    dest = destination or os.path.basename(path)
    _run[f"artifacts/{dest}"].upload(path)
    print(f"[neptune] Uploaded artifact: {path}")


def end_run() -> None:
    """Stop the active Neptune run."""
    global _run
    if _run and NEPTUNE_AVAILABLE and not isinstance(_run, dict):
        _run.stop()
        print("[neptune] Run stopped")
    _run = None


# ── Standalone smoke-test ──────────────────────────────────────────────────
if __name__ == "__main__":
    import yaml

    with open("params.yaml") as f:
        params = yaml.safe_load(f)

    run = start_run(name="smoke-test", tags=["test"])
    log_params(params.get("train", {}))
    log_metrics({"accuracy": 0.91, "f1": 0.89}, step=1)
    log_metrics({"accuracy": 0.93, "f1": 0.91}, step=2)
    end_run()
    print("Smoke test complete.")