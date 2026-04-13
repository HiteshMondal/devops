# Prefect — Workflow Orchestration
## Complete Documentation for the MLOps Project

---

## Table of Contents

1. [What is Prefect?](#what-is-prefect)
2. [Why Prefect Exists — The Problem It Solves](#why-prefect-exists)
3. [Core Architecture](#core-architecture)
4. [Key Concepts](#key-concepts)
5. [Prefect vs Other Orchestrators](#prefect-vs-other-orchestrators)
6. [How Prefect Works Internally](#how-prefect-works-internally)
7. [File-by-File Breakdown](#file-by-file-breakdown)
8. [Task Deep Dive — check_drift()](#task-deep-dive--check_drift)
9. [Task Deep Dive — retrain()](#task-deep-dive--retrain)
10. [Flow Deep Dive — retraining_flow()](#flow-deep-dive--retraining_flow)
11. [deploy_prefect.sh — What It Does Step by Step](#deploy_prefectsh)
12. [Ephemeral Server Mode](#ephemeral-server-mode)
13. [Retry Behaviour](#retry-behaviour)
14. [Environment Variables](#environment-variables)
15. [Common Prefect Commands](#common-prefect-commands)
16. [How Prefect Connects to Other Tools](#how-prefect-connects-to-other-tools)

---

## What is Prefect?

Prefect is a Python-native workflow orchestration platform. It lets you define a series of tasks, wire them together into a flow, and run the flow with automatic retry handling, state tracking, logging, and observability — all with plain Python code decorated with `@task` and `@flow`.

Unlike traditional schedulers (cron, Airflow) which require XML or YAML configuration, Prefect workflows are pure Python. Any Python function can become a task by adding `@task`, and any function that calls tasks becomes a flow by adding `@flow`. This makes Prefect extremely easy to adopt in an existing Python codebase.

Prefect 3.x (used in this project) runs in **ephemeral mode** by default — no persistent server is required for local execution. A temporary server starts, the flow runs, and the server shuts down. For production use, a persistent Prefect server or Prefect Cloud provides a full UI with run history, logs, and scheduling.

---

## Why Prefect Exists

A machine learning system that trains and serves a model faces a recurring operational problem: **the model degrades over time as real-world data drifts away from training data**, but nobody is watching. Accuracy drops silently until users notice bad predictions.

The naive solution is a cron job that retrains on a schedule. But this has problems:

- It retrains even when nothing has drifted, wasting compute.
- If training fails, the cron job silently exits and nothing is retried.
- There is no record of what ran, when, and whether it succeeded.
- The logic that decides when to retrain is buried in a shell script with no observability.

Prefect solves all of these by turning the retraining decision into a first-class workflow:

- **Conditional execution** — retraining only triggers when drift is actually detected.
- **Automatic retries** — if `check_drift` fails because the drift file is locked, Prefect retries it up to two times with a 30-second delay before giving up.
- **State tracking** — every run is recorded with its start time, end time, and final state (Completed, Failed, Retrying).
- **Clean Python** — the entire workflow is readable Python, not YAML or shell scripts.

---

## Core Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Prefect Flow Definition                   │
│                                                              │
│   @flow retraining_flow()                                    │
│       │                                                      │
│       ├── @task check_drift()     retries=2, delay=30s      │
│       │       │                                              │
│       │       └── reads drift_summary.json                   │
│       │           returns True / False                       │
│       │                                                      │
│       └── @task retrain()         retries=1, delay=60s      │
│               │  (only if drift detected)                    │
│               └── subprocess: training_flow.py run          │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ runs inside
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Prefect Ephemeral Server (temporary)            │
│  Starts on a random local port (e.g. http://127.0.0.1:8016) │
│  Tracks task states, retries, logs during the flow run      │
│  Shuts down automatically when the flow completes           │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ metadata stored in
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              PREFECT_HOME (.platform/prefect/)               │
│  SQLite database: run history, task states, logs             │
│  Reset on each deploy_prefect.sh run (ephemeral mode)        │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Concepts

### Flow
A Prefect Flow is the top-level workflow definition — a Python function decorated with `@flow`. It wires tasks together and defines the execution logic. In this project, `retraining_flow()` is the flow. It calls `check_drift()`, inspects the result, and conditionally calls `retrain()`.

### Task
A Prefect Task is a single unit of work — a Python function decorated with `@task`. Tasks are the building blocks of flows. Prefect tracks each task's state (Pending, Running, Completed, Failed, Retrying) independently. In this project there are two tasks: `check_drift()` and `retrain()`.

### State
Every task and flow run has a Prefect State. The main states are:

| State | Meaning |
|---|---|
| Pending | Scheduled but not yet started |
| Running | Currently executing |
| Completed | Finished successfully |
| Failed | Raised an exception and exhausted retries |
| Retrying | Failed but has retries remaining |
| Crashed | Process was killed unexpectedly |

### Run
Each execution of a flow is a **flow run**. Each execution of a task within a flow is a **task run**. Prefect assigns unique IDs to runs and tracks their full lifecycle.

### Retry
When a task raises an exception, Prefect catches it and, if retries are configured, waits for `retry_delay_seconds` before trying again. The task's state becomes `Retrying` during this window.

### Deployment
A Prefect Deployment wraps a flow definition with scheduling configuration (interval, cron, etc.) and infrastructure settings (which worker pool to use, what environment to run in). In this project the flow runs directly without a deployment — a deployment would be added to schedule it to run daily.

### Worker / Work Pool
In production Prefect, workers poll work pools for scheduled flow runs and execute them. In ephemeral mode (this project), there is no worker — the flow runs directly in the current process.

---

## Prefect vs Other Orchestrators

| Feature | Prefect | Airflow | Metaflow | Kubeflow |
|---|---|---|---|---|
| Definition language | Python | Python DAG | Python class | Python + YAML |
| Server required | Optional (ephemeral) | Yes | No | Yes (K8s) |
| Retry handling | Built-in per task | Built-in per task | Manual | Per step |
| Primary use case | Workflow orchestration | DAG scheduling | ML training steps | K8s ML pipelines |
| Role in this project | Drift-triggered retraining | Scheduled daily pipeline | Model training steps | Compile pipeline YAML |

In this project, Prefect and Airflow serve different but complementary roles:

- **Airflow** runs the full MLOps pipeline on a daily schedule (preprocess → train → evaluate → register).
- **Prefect** runs reactively — it checks for drift and retrains only when needed. It is the event-driven watchdog, while Airflow is the time-driven scheduler.

---

## How Prefect Works Internally

When you call `retraining_flow()`, Prefect does the following:

1. **Starts an ephemeral server** on a random localhost port. This server is a lightweight FastAPI application that tracks task states in a SQLite database stored in `PREFECT_HOME`.

2. **Creates a flow run** with a unique ID, records its start time, and sets its state to Running.

3. **Calls `check_drift()`** — but not directly. Prefect wraps the call in its task engine, which:
   - Creates a task run record with a unique ID.
   - Executes the function body.
   - Catches any exception.
   - If an exception is caught and retries remain, sets state to Retrying and waits.
   - If successful, sets state to Completed and returns the result.

4. **The flow function receives the task result** — in Prefect 3.x, task calls inside a flow return the actual value (not a Future), so `drift_detected` is a plain Python `bool`.

5. **Conditionally calls `retrain()`** based on the bool result.

6. **Sets the flow run state** to Completed or Failed depending on whether any task failed and exhausted retries.

7. **Shuts down the ephemeral server** and cleans up.

The log lines you see in the terminal — `INFO | Task run 'check_drift' - Finished in state Completed()` — come from Prefect's internal task engine reporting state transitions.

---

## File-by-File Breakdown

### `ml/pipelines/prefect/retraining_flow.py` — Flow Definition

This is the core Prefect workflow. It contains two tasks and one flow.

#### Imports and Helpers

```python
from prefect import flow, task
```

Only two imports are needed from Prefect. The `@flow` and `@task` decorators are the entire Prefect API surface used here.

The `_log()` and `_banner()` helper functions provide coloured terminal output. They are plain Python and have nothing to do with Prefect — they run inside task functions just like any other code.

---

#### `@task check_drift() → bool`

```python
@task(retries=2, retry_delay_seconds=30)
def check_drift() -> bool:
```

**What it does:** Reads `monitoring/evidently/reports/drift_summary.json` and extracts the `share_of_drifted_columns` metric. Compares it to the `DRIFT_THRESHOLD` environment variable (default 10%). Returns `True` if drift exceeds the threshold, `False` otherwise.

**Retry configuration:** `retries=2, retry_delay_seconds=30` means if this task raises any exception (e.g., the drift file is being written by Evidently at the same time and is temporarily locked, or a JSON parse error occurs), Prefect will wait 30 seconds and try again. It will make at most 3 total attempts (1 original + 2 retries) before marking the task as Failed.

**Return value:** A plain Python `bool`. Prefect serialises this into its state store and makes it available to the flow function.

**JSON navigation:** The drift share is extracted with defensive navigation:
```python
drift_share = (
    summary
    .get("metrics", [{}])[0]
    .get("result", {})
    .get("share_of_drifted_columns", 0.0)
)
```
This handles the Evidently JSON structure where the drift share is nested inside the first element of the `metrics` array. If any key is missing, it defaults to `0.0` (no drift), which is the safe fallback.

**No-report handling:** If `drift_summary.json` does not exist (first run before Evidently has ever executed), the task returns `False` and logs a warning. It does not raise an exception, so no retry is triggered.

---

#### `@task retrain()`

```python
@task(retries=1, retry_delay_seconds=60)
def retrain():
```

**What it does:** Calls `ml/pipelines/metaflow/training_flow.py run` as a subprocess. This triggers the full Metaflow training pipeline: load data → train RandomForest → evaluate → save model.pkl → log to MLflow/Comet → emit OpenLineage events.

**Why subprocess?** Using `subprocess.run` keeps Prefect isolated from Metaflow's dependencies. If Metaflow, scikit-learn, or MLflow have version conflicts with Prefect's dependencies, running them in a subprocess avoids the conflict entirely. Prefect simply starts the process and waits for it to exit.

**`capture_output=False`** means Metaflow's output streams directly to the terminal in real time. You see every `[TRAIN]`, `[EVAL]`, and `[SAVE]` log line as it happens rather than getting a wall of text at the end.

**`check=True`** means if the subprocess exits with a non-zero return code (training failed), Python raises `subprocess.CalledProcessError`. Prefect catches this, decrements the retry counter, waits 60 seconds, and tries again.

**Retry configuration:** `retries=1, retry_delay_seconds=60` — one retry with a 60-second delay. Training failures are often transient (out-of-memory, file lock, network timeout to MLflow), so one retry with a longer delay is appropriate.

---

#### `@flow retraining_flow()`

```python
@flow(
    name="retraining-flow",
    description="Checks Evidently drift report → retrains model via Metaflow if drift detected",
)
def retraining_flow():
```

**What it does:** The top-level orchestrator. Calls `check_drift()`, inspects the result, and conditionally calls `retrain()`.

**The `.result()` call:**
```python
result = drift_detected.result() if hasattr(drift_detected, "result") else drift_detected
```
This compatibility line handles both Prefect 2.x (where task calls inside flows return `PrefectFuture` objects that need `.result()`) and Prefect 3.x (where they return plain values directly). The `hasattr` check makes the code work with either version.

**Conditional branching:** Standard Python `if/else` — no special Prefect construct needed. Prefect's power is that you use regular Python control flow and it handles the state tracking around it.

**`name` parameter:** The flow name `"retraining-flow"` is what appears in the Prefect UI and in log output. It is separate from the Python function name.

---

### `ml/pipelines/prefect/deploy_prefect.sh` — Deployment Script

This script prepares the environment and executes the flow. It is called by `run.sh` as part of the MLOps pipeline deployment.

---

## deploy_prefect.sh — What It Does Step by Step

**Variable setup:**
```bash
PREFECT_VENV="$PROJECT_ROOT/.platform/venvs/prefect"
PREFECT_HOME="$PROJECT_ROOT/.platform/prefect"
FLOW_FILE="$PROJECT_ROOT/ml/pipelines/prefect/retraining_flow.py"
export FLOW_FILE
export PROJECT_ROOT
```
Both `FLOW_FILE` and `PROJECT_ROOT` are exported so they are available as environment variables inside the Python heredoc that executes the flow. Without `export`, the variables exist only in the shell and Python's `os.environ` cannot see them.

**Validate environment:**
```bash
if [[ ! -f "$FLOW_FILE" ]]; then
    echo "[prefect] ERROR: Flow file missing"
    exit 1
fi
```
Fails fast with a clear error if the flow file does not exist, rather than letting the error surface deep inside Python.

**Prepare runtime directory:**
```bash
mkdir -p "$PREFECT_HOME"
export PREFECT_HOME="$PREFECT_HOME"
```
`PREFECT_HOME` tells Prefect where to store its SQLite database and metadata. By pointing it at `.platform/prefect/` inside the project, the Prefect state is isolated from any system-wide Prefect installation.

**Environment configuration:**
```bash
export PREFECT_SERVER_ALLOW_EPHEMERAL_MODE="true"
export PREFECT_API_SERVICES_LATE_RUNS_ENABLED="false"
export PREFECT_RUNNER_PROCESS_LIMIT=1
export PREFECT_EPHEMERAL_STARTUP_TIMEOUT_SECONDS=120
export PREFECT_TELEMETRY_ENABLED="false"
```
These variables configure the ephemeral server. `PREFECT_SERVER_ALLOW_EPHEMERAL_MODE=true` enables the temporary server mode. `PREFECT_TELEMETRY_ENABLED=false` suppresses the telemetry error that appeared in the terminal output when Prefect tried to phone home to Prefect Cloud's analytics endpoint.

**Create isolated virtual environment:**
```bash
if [[ ! -d "$PREFECT_VENV" ]]; then
    python3 -m venv "$PREFECT_VENV"
fi
```
A dedicated venv at `.platform/venvs/prefect/` isolates Prefect's dependencies from the system Python and from other tools' venvs (Feast uses `/tmp/devops-feast-venv/`, Evidently uses its own venv). This prevents dependency conflicts.

**Install dependencies:**
```bash
"$PREFECT_VENV/bin/pip" install --quiet \
    "prefect>=3,<4" \
    "fakeredis==2.19.0" \
    "redis==4.6.0" \
    "sqlalchemy<2.1" \
    "alembic<1.14"
```
The pinned versions matter. `sqlalchemy<2.1` and `alembic<1.14` avoid breaking changes in newer versions that are incompatible with Prefect 3.x's database schema. `fakeredis` and `redis` are included because Prefect 3.x's ephemeral server uses Redis-compatible queuing internally — `fakeredis` provides an in-memory implementation so no real Redis server is needed.

**Reset metadata cache:**
```bash
rm -rf "$PREFECT_HOME"
mkdir -p "$PREFECT_HOME"
```
Deletes the Prefect SQLite database before each run. This ensures a clean state — no stale run records, no database migration issues from version changes. In a production Prefect deployment you would not do this (you want the run history), but for local ephemeral execution it prevents accumulation of stale data.

**Execute the flow via heredoc:**
```python
"$PREFECT_VENV/bin/python" - <<'PYEOF'
import sys, os
sys.path.insert(0, os.environ.get("PROJECT_ROOT", "."))
import importlib.util
spec = importlib.util.spec_from_file_location("retraining_flow", os.environ["FLOW_FILE"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.retraining_flow.fn()
PYEOF
```

This is the key execution step. Breaking it down:

- `<<'PYEOF'` — single-quoted heredoc. Shell does **not** expand `$variables` inside it. Python reads the literal text, which is correct here because the values are passed via `os.environ`, not shell substitution.
- `sys.path.insert(0, PROJECT_ROOT)` — adds the project root to Python's import path so `retraining_flow.py` can import from `ml/` and `app/`.
- `importlib.util.spec_from_file_location` — loads `retraining_flow.py` by absolute path (from `$FLOW_FILE` env var) without needing it to be on `sys.path` or installed as a package.
- `mod.retraining_flow.fn()` — calls the **underlying function** of the flow directly, bypassing Prefect's server/client infrastructure. `.fn()` is Prefect's escape hatch for running the flow logic without the full orchestration machinery. This is what solved the original ephemeral server timeout error.

---

## Ephemeral Server Mode

Prefect 3.x introduced ephemeral mode as a way to run flows without a persistent server. When a flow runs in ephemeral mode:

1. Prefect starts a lightweight FastAPI server on a random localhost port.
2. The server creates a SQLite database in `PREFECT_HOME` to track states.
3. The flow and its tasks run, with state transitions recorded in the SQLite DB.
4. When the flow completes, the server shuts down.

The server start is what caused the original `Timed out while attempting to connect to ephemeral Prefect API server` error. The fix was to call `mod.retraining_flow.fn()` instead of `mod.retraining_flow()` — the `.fn()` approach runs the flow function's body directly without starting the ephemeral server.

The tradeoff of using `.fn()` is that Prefect's state tracking, retry handling, and logging are partially bypassed. For production use, running `mod.retraining_flow()` with a properly configured Prefect server is the right approach. For local orchestration via `run.sh`, `.fn()` provides the workflow logic without the server overhead.

---

## Retry Behaviour

Prefect's retry system works at the task level, not the flow level. Here is exactly what happens when `check_drift()` fails:

```
Attempt 1: check_drift() raises FileNotFoundError
  → Prefect catches the exception
  → State: Retrying (1 retry remaining)
  → Waits 30 seconds

Attempt 2: check_drift() raises FileNotFoundError again
  → Prefect catches the exception
  → State: Retrying (0 retries remaining)
  → Waits 30 seconds

Attempt 3: check_drift() raises FileNotFoundError again
  → Prefect catches the exception
  → No retries remaining
  → State: Failed
  → Flow run state: Failed
```

If any attempt succeeds, the state immediately becomes Completed and the retry count is reset. The retry state and attempt number are visible in the Prefect UI and in the terminal log output.

---

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `PROJECT_ROOT` | Derived from script path | Absolute path to the project root. Used by the flow to locate `drift_summary.json` and `training_flow.py`. |
| `FLOW_FILE` | `$PROJECT_ROOT/ml/pipelines/prefect/retraining_flow.py` | Absolute path to the flow file. Exported so the Python heredoc can load it via `os.environ`. |
| `DRIFT_THRESHOLD` | `0.1` | Fraction of features that must drift before retraining is triggered. `0.1` means 10%. |
| `PREFECT_HOME` | `.platform/prefect/` | Directory where Prefect stores its SQLite database and metadata. |
| `PREFECT_SERVER_ALLOW_EPHEMERAL_MODE` | `true` | Enables temporary in-process server mode without a persistent Prefect deployment. |
| `PREFECT_TELEMETRY_ENABLED` | `false` | Disables Prefect's telemetry calls to Prefect Cloud analytics. Prevents connection error noise. |
| `PREFECT_EPHEMERAL_STARTUP_TIMEOUT_SECONDS` | `120` | How long to wait for the ephemeral server to start before timing out. |
| `PREFECT_API_SERVICES_LATE_RUNS_ENABLED` | `false` | Disables a background service that is not needed for single-run local execution. |

---

## Common Prefect Commands

| Command | What It Does |
|---|---|
| `python retraining_flow.py` | Run the flow directly |
| `prefect server start` | Start a persistent Prefect UI server |
| `prefect deployment build flow.py:retraining_flow --name daily` | Create a deployment |
| `prefect deployment apply retraining_flow-deployment.yaml` | Register a deployment |
| `prefect deployment run retraining-flow/daily` | Trigger a deployment run |
| `prefect flow-run ls` | List recent flow runs |
| `prefect task-run ls` | List recent task runs |
| `prefect work-pool create default-pool` | Create a work pool for workers |
| `prefect worker start --pool default-pool` | Start a worker |
| `prefect profile ls` | List Prefect configuration profiles |

---

## How Prefect Connects to Other Tools

**Evidently** — `check_drift()` reads `monitoring/evidently/reports/drift_summary.json`, which is written by `drift_detection.py`. Evidently is the sensor; Prefect is the responder. If Evidently has not run yet, `check_drift()` returns `False` and logs a warning rather than failing.

**Metaflow** — `retrain()` calls `training_flow.py run` as a subprocess. Prefect is the decision-maker (should we retrain?); Metaflow is the executor (how do we retrain?). Prefect provides retry logic around the Metaflow invocation, so if Metaflow fails once, Prefect retries it after 60 seconds.

**MLflow** — Metaflow's training steps log to MLflow internally. Prefect does not interact with MLflow directly but enables the workflow that ultimately produces a new MLflow model version for promotion.

**FastAPI** — The `/retrain` endpoint in `app/src/main.py` calls `retraining_flow.py` as a background subprocess. This means Prefect can also be triggered on-demand by an HTTP call, not just by `run.sh`. The same flow definition serves both the automated drift-triggered path and the manual HTTP-triggered path.

**Airflow** — Airflow runs the daily scheduled pipeline (preprocess → train → evaluate → register). Prefect runs reactively when drift is detected. They are complementary: Airflow is the clock-based trigger, Prefect is the condition-based trigger. In a deployment where both are running, Prefect may fire between Airflow's daily runs if drift appears suddenly.

**DVC** — DVC defines and caches the pipeline stages. Prefect's `retrain()` task invokes Metaflow directly (not `dvc repro`), which means the new model.pkl produced by drift-triggered retraining is not automatically tracked by DVC. To close this loop in production, `retrain()` could call `dvc repro` instead of `training_flow.py run`, which would give DVC-tracked reproducibility for every retrain.

**OpenLineage** — When Metaflow runs inside `retrain()`, it calls `emit_training_lineage()`, which sends START and COMPLETE events to the OpenLineage backend. Prefect's task boundary (start of `retrain()` to end of `retrain()`) maps directly to a Metaflow run, which maps directly to the OpenLineage job `training_flow.train`. The lineage graph records that this particular model.pkl was produced by a Prefect-triggered retraining run.

---

## Summary

Prefect is the reactive watchdog of this MLOps system. It sits between Evidently (drift detection) and Metaflow (model training), reading the drift report and triggering retraining only when needed. The `@task` and `@flow` decorators add retry handling, state tracking, and clear log output with minimal code change — the underlying logic in `check_drift()` and `retrain()` is plain Python that would work without Prefect, but Prefect gives it resilience and observability.

The deployment script (`deploy_prefect.sh`) handles all the environmental setup — isolated venv, pinned dependencies, clean metadata state — so the flow runs reliably in local development, CI pipelines, and Kubernetes jobs without any manual configuration.