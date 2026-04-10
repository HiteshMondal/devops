# MLOps App — Documentation

> A production-grade MLOps serving layer that ties together data preparation, feature engineering, model training, drift monitoring, and live predictions under a single FastAPI application.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Pipeline Stages](#3-pipeline-stages)
   - [Stage 1 — Data Preparation (`prepare.py`)](#stage-1--data-preparation-preparepy)
   - [Stage 2 — Feature Engineering (`features.py`)](#stage-2--feature-engineering-featurespy)
   - [Stage 3 — Train/Test Split (`split.py`)](#stage-3--traintest-split-splitpy)
   - [Stage 4 — Model Evaluation (`evaluate.py`)](#stage-4--model-evaluation-evaluatepy)
4. [FastAPI Application (`main.py`)](#4-fastapi-application-mainpy)
   - [Startup Sequence](#startup-sequence)
   - [API Endpoints](#api-endpoints)
5. [Integrated MLOps Tools](#5-integrated-mlops-tools)
6. [Configuration](#6-configuration)
7. [Dependencies](#7-dependencies)
8. [Data Flow — End to End](#8-data-flow--end-to-end)
9. [Quality Gates](#9-quality-gates)
10. [Running the Application](#10-running-the-application)

---

## 1. Project Overview

This application is the central serving layer of an MLOps system. It:

- Exposes a REST API (built with **FastAPI**) for predictions, metrics, drift monitoring, and model management.
- Orchestrates a four-stage data and training pipeline managed by **DVC**.
- Integrates with eight industry-standard MLOps tools: MLflow, Feast, Evidently, Prefect, WhyLogs, OpenLineage, DVC, and LakeFS.
- Handles model lifecycle management from raw data ingestion through to production promotion.

The guiding principle is **reproducibility**: every data transformation, training run, and deployment decision is tracked, versioned, and auditable.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLIENT / KUBERNETES                         │
│         (HTTP requests, liveness probes, readiness probes)          │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   FastAPI Application  (main.py)                    │
│                                                                     │
│  /predict   /metrics   /drift   /retrain   /model/info   /features  │
│  /health    /ready     /lineage /tools/status    /                  │
└──────┬──────────┬──────────┬────────────┬────────────┬──────────────┘
       │          │          │            │            │
       ▼          ▼          ▼            ▼            ▼
  RandomForest  MLflow   Evidently    Prefect →    Feast
  model.pkl    Registry  drift        Metaflow     Online
               (promote  reports      retrain      Store
               to Prod)               flow
                              │
                    ┌─────────▼──────────┐
                    │  DVC Pipeline      │
                    │  prepare.py        │
                    │      ↓             │
                    │  features.py       │
                    │      ↓             │
                    │  split.py          │
                    │      ↓             │
                    │  evaluate.py       │
                    └────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
          WhyLogs        OpenLineage        LakeFS
       (per-request       (lineage          (dataset
        profiling)         graph)          versioning)
```

The application sits at the intersection of **serving** (predictions, feature lookups) and **management** (retraining triggers, drift detection, model promotion). Every integrated tool plays a specific role — none overlap.

---

## 3. Pipeline Stages

The pipeline is a four-step DVC workflow. Each stage takes the output of the previous one and passes it to the next. DVC hashes every input and output so that only stages affected by a change are re-run.

```
Raw CSV  →  prepare.py  →  features.py  →  split.py  →  evaluate.py
```

---

### Stage 1 — Data Preparation (`prepare.py`)

**Purpose:** Read the raw dataset, clean it, and save a processed version for downstream stages.

**Where it fits:** This is Step 1 of the DVC pipeline. Its output (`processed_path`) is the input for `features.py`.

#### Functions

| Function | What it does |
|---|---|
| `load_data(path)` | Reads the raw CSV from disk into a pandas DataFrame. Raises a clear `FileNotFoundError` with instructions if the file is missing. |
| `preprocess(df)` | Drops rows with null values (required by sklearn). Normalises column names to lowercase with underscores (e.g., `"Feature 1"` → `"feature_1"`). |
| `save_processed(df, path)` | Saves the cleaned DataFrame to the processed data directory. DVC tracks this file's MD5 hash and marks the training stage as stale if it changes. |
| `load_model(path)` | Loads a serialised `.pkl` model from disk. Used by `main.py` at startup to load the model into memory for the `/predict` endpoint. |

#### Key Design Decisions

- **Null handling:** Rows with any null value are dropped before saving. sklearn will raise an error if it receives NaN inputs, so this is a hard requirement.
- **Column normalisation:** Consistent column naming prevents a category of subtle bugs where training uses `"Feature 1"` and serving uses `"feature_1"`, causing the model to receive data in the wrong column order.
- **OpenLineage integration:** After saving, the script attempts to emit a lineage event to Marquez (`emit_preprocessing_lineage()`). This is non-fatal — if Marquez is not running, a warning is logged and execution continues.

---

### Stage 2 — Feature Engineering (`features.py`)

**Purpose:** Transform the cleaned data into a format that sklearn models can consume directly.

**Where it fits:** This is Step 2 of the DVC pipeline. It reads from `processed_path` and writes to `features_path`.

#### Transformations Applied

**Numeric Scaling — `StandardScaler`**

Subtracts the mean from each numeric column and divides by the standard deviation. After scaling, each feature has mean ≈ 0 and standard deviation ≈ 1. This prevents features with large magnitudes (e.g., salary: 20,000–200,000) from dominating features with small magnitudes (e.g., age: 0–100) in distance-based or gradient-based models.

**Categorical Encoding — `OneHotEncoder`**

Converts string-valued columns into binary indicator columns. For example, a column `color` with values `red`, `blue`, `green` becomes three new binary columns: `color_red`, `color_blue`, `color_green`. sklearn cannot process string values directly — encoding is mandatory.

#### Configuration

Both the list of numeric columns and the list of categorical columns are read from `ml/configs/params.yaml` under `features.numeric` and `features.categorical`. If either list is empty, that transformation step is skipped with a warning — no crash.

#### Feast Integration

The output feature matrix from this stage is also converted to Parquet by `apply_features.sh` so that Feast can serve the same features at prediction time. This guarantees that training and serving use identical feature transformations (preventing "training-serving skew").

---

### Stage 3 — Train/Test Split (`split.py`)

**Purpose:** Split the feature matrix into a training set and a held-out test set.

**Where it fits:** This is Step 3 of the DVC pipeline. It reads from `features_path` and writes to `train_path` and `test_path`.

#### Why We Split

If we measured model accuracy on the same data we trained on, we would get misleadingly high scores — the model effectively "memorised" the training answers. The held-out test set provides an honest estimate of how the model will perform on real, unseen data.

#### Configuration (from `params.yaml`)

| Parameter | Default | Meaning |
|---|---|---|
| `test_size` | `0.2` | 20% of rows go to `test.csv`; 80% go to `train.csv` |
| `random_state` | Fixed integer | The same seed always produces the same split, making results reproducible across machines and runs |

The split ratio and random seed are versioned in `params.yaml` alongside the data, so any change to either is tracked by DVC.

---

### Stage 4 — Model Evaluation (`evaluate.py`)

**Purpose:** Load the trained model, run it against the test set, compute accuracy and F1 score, check quality gates, and save `eval_metrics.json`.

**Where it fits:** This is the final stage of the DVC pipeline. It reads the model from `model_output` and the test data from `test_path`.

#### Metrics Computed

| Metric | Method | Description |
|---|---|---|
| Accuracy | `accuracy_score` | Fraction of test rows predicted correctly |
| F1 Score | `f1_score(average="weighted")` | Harmonic mean of precision and recall, weighted by class frequency |

Both metrics are written to `eval_metrics.json`. This file is the single source of truth for downstream tools.

#### Quality Gate Logic

The script compares metrics against configurable thresholds:

```
passed = (accuracy >= MLOPS_MIN_ACCURACY) AND (f1 >= MLOPS_MIN_F1)
```

Thresholds are read from environment variables (`MLOPS_MIN_ACCURACY`, `MLOPS_MIN_F1`) with defaults of `0.75` and `0.70` respectively.

**If the model passes:** `deploy_mlflow.sh` promotes the model to Production in the MLflow Model Registry. The Airflow DAG routes to the `register_model` task.

**If the model fails:** The model stays in Staging. The script logs clear instructions to tune hyperparameters in `params.yaml` and retrain.

#### Additional Output

- A full `classification_report` (precision, recall, F1 per class) is printed to the terminal.
- A `confusion_matrix` (rows = actual labels, columns = predicted labels) is printed.
- `eval_metrics.json` is saved to `metrics_path` and served by `GET /metrics/summary`.

---

## 4. FastAPI Application (`main.py`)

`main.py` is the entry point of the serving layer. It loads the trained model at startup and exposes all functionality over HTTP.

### Startup Sequence

When the application starts (managed by the `lifespan` async context manager):

1. **Tool probing** — `_probe_tools()` is called. It checks every integrated MLOps tool (MLflow, Feast, Evidently, Prefect, WhyLogs, OpenLineage, DVC, LakeFS) and caches the result. Results are printed as a color-coded summary in the terminal.

2. **Model loading** — The trained RandomForest model is loaded from `ml/models/artifacts/model.pkl` using `load_model()` from `prepare.py`. If the file does not exist, a clear error message with training instructions is logged. The `/ready` endpoint returns 503 until this step succeeds.

3. **Ready banner** — A banner is printed showing the port, number of active tools, and number of inactive tools.

---

### API Endpoints

#### `GET /`
Returns a summary of the application: name, environment, model status, uptime, and the list of currently active MLOps tools.

---

#### `GET /health`
**Kubernetes liveness probe.** Returns `200 OK` as long as the process is running. If this endpoint stops responding, Kubernetes restarts the pod. Also used by the `Dockerfile HEALTHCHECK` every 30 seconds.

Response:
```json
{ "status": "ok", "uptime_s": 142.5 }
```

---

#### `GET /ready`
**Kubernetes readiness probe.** Returns `200 OK` only after the model has been successfully loaded into memory. Kubernetes does not route traffic to the pod until this endpoint returns `200`. Returns `503` if the model is not loaded yet.

---

#### `POST /predict`
**Main prediction endpoint.** Accepts three numeric features and returns the model's predicted class, class probabilities, model name, and response latency.

Request body:
```json
{ "feature_1": 0.5, "feature_2": -0.3, "feature_3": 7.2 }
```

Response:
```json
{
  "prediction": 1,
  "probability": [0.12, 0.88],
  "model_name": "baseline-v1",
  "latency_ms": 3.2
}
```

**Internal flow:**
1. Pydantic validates the request body automatically.
2. The feature array is passed to `model.predict()` and `model.predict_proba()`.
3. WhyLogs profiles the request in a **background task** (never adds latency to the response).
4. The prediction, probabilities, and latency are returned.

Returns `503` if the model has not been loaded. Returns `500` if the model raises an exception during prediction.

---

#### `GET /metrics/summary`
Returns two categories of metrics:

- **`training_metrics`** — accuracy, F1, and quality gate results from the most recent training run (read from `eval_metrics.json`).
- **`request_stats`** — live counters since the app last started: total predictions, total errors, and average response latency.

Also shows quality gate thresholds and whether the current model passes them.

---

#### `GET /drift/summary`
Returns the latest Evidently drift report.

**What is drift?** Drift means the distribution of live data arriving at `/predict` has shifted compared to the training data. For example, if `feature_1` used to range 0–10 but now ranges 50–100, the model's predictions will silently degrade.

**How it works:**
1. `drift_detection.py` compares the live prediction log against training data and writes `drift_summary.json`.
2. This endpoint reads that file and computes whether `drift_share` exceeds the `DRIFT_THRESHOLD` (default: `0.1`, i.e., 10% of features).
3. The response includes a human-readable status (`healthy` or `drift_detected`) and a recommendation.

If no report exists, instructions to run `drift_detection.py` are returned.

---

#### `POST /retrain`
Triggers the full retraining pipeline in a background task. The HTTP response is immediate — training happens asynchronously.

**What runs in the background:**
1. **Prefect** (`retraining_flow.py`) orchestrates the workflow, checks drift status, and decides whether retraining is needed.
2. **Metaflow** (`training_flow.py`) trains a new RandomForest model, saves `model.pkl` and `eval_metrics.json`.
3. Experiment trackers (MLflow, Neptune, Comet) log the run with params, metrics, and the model artifact.
4. **OpenLineage** records the data lineage graph for the new run.
5. The app reloads the newly trained model into memory automatically.

After calling this endpoint, check `/metrics/summary` in approximately 30 seconds to see updated metrics.

---

#### `GET /model/info`
Queries the MLflow Model Registry for the model currently in the `Production` stage.

**How model promotion works:**
1. `training_flow.py` logs the model to MLflow and registers it as a new version.
2. `deploy_mlflow.sh` reads `eval_metrics.json` and promotes the version to `Production` if it passes quality gates.
3. This endpoint shows which version is currently serving predictions.

If the MLflow server is unreachable, falls back to reading `eval_metrics.json` from disk.

---

#### `GET /features/{row_id}`
Retrieves pre-computed features for a given `row_id` from the Feast online store.

**Why use a Feature Store?** Without a Feature Store, the feature transformation logic might differ between training (in Python notebooks) and serving (in the API). Feast ensures the exact same transformation is used in both contexts, preventing "training-serving skew."

**Setup required:** Run `bash ml/feature_store/feast/apply_features.sh` to materialise features into the SQLite online store before calling this endpoint.

---

#### `GET /lineage/summary`
Returns a summary of OpenLineage events recorded for the current session, along with the pipeline graph (which stage produces which file) and Marquez reachability status.

**Data lineage** answers the question: "Where did the data for this model come from?" It records the full journey — raw CSV → `prepare.py` → processed CSV → `training_flow.py` → `model.pkl`.

---

#### `GET /tools/status`
Re-probes every MLOps tool at request time (not cached) and returns a detailed status for each one, including whether it is active, its purpose, its current detail message, and a setup hint if it is inactive.

---

## 5. Integrated MLOps Tools

| Tool | Role | How It's Used |
|---|---|---|
| **MLflow** | Experiment tracking + Model Registry | Logs every training run with params, metrics, and artifacts. `deploy_mlflow.sh` promotes models to Production when quality gates pass. |
| **Feast** | Feature Store | Stores pre-computed features in a SQLite online store. `GET /features/{id}` retrieves them. Prevents training-serving skew. |
| **Evidently** | Data drift detection | Compares live prediction data against training data. Drift reports are read by `GET /drift/summary` and by Prefect's retraining flow. |
| **Prefect** | Workflow orchestration | Orchestrates the retraining workflow triggered by `POST /retrain`. Calls the Metaflow training pipeline as a subprocess. |
| **WhyLogs** | Prediction profiling | Profiles every call to `POST /predict` (feature statistics, value distributions) in a background task. Used to spot data quality issues. |
| **OpenLineage** | Data lineage | Records each pipeline step (raw → processed → trained) as events. Marquez visualises these as a graph. |
| **DVC** | Data versioning | Versions data files and pipeline stages with MD5 hashes. Ensures every team member uses the same data version and only re-runs affected stages. |
| **LakeFS** | Data lake versioning | Provides Git-like branches and commits for entire datasets stored in S3 or local storage. |

Each tool is probed at startup by `_probe_tools()`. Tools that are unreachable or not installed are marked as inactive — they do not crash the application. Setup hints for each inactive tool are shown in `GET /tools/status`.

---

## 6. Configuration

All pipeline parameters are centralised in `ml/configs/params.yaml`. This file is versioned by DVC, meaning any change is tracked alongside the data.

Key parameter groups:

| Group | Parameters |
|---|---|
| `dataset` | `raw_path`, `processed_path`, `features_path`, `train_path`, `test_path`, `target_column`, `test_size`, `random_state` |
| `features` | `numeric` (list of numeric column names), `categorical` (list of categorical column names) |
| `training` | `model_output` (path to `model.pkl`), `metrics_output` (path to `eval_metrics.json`) |

Environment variables can override quality gate thresholds:

| Variable | Default | Meaning |
|---|---|---|
| `MLOPS_MIN_ACCURACY` | `0.75` | Minimum accuracy for Production promotion |
| `MLOPS_MIN_F1` | `0.70` | Minimum F1 score for Production promotion |
| `DRIFT_THRESHOLD` | `0.1` | Fraction of drifted features that triggers a retraining recommendation |
| `MLFLOW_TRACKING_URI` | Cluster-internal URL | Where to find the MLflow tracking server |
| `OPENLINEAGE_URL` | `http://localhost:5000` | Where to find the Marquez server |
| `LAKEFS_ENDPOINT` | `http://localhost:8001` | Where to find the LakeFS server |
| `MODEL_PATH` | `ml/models/artifacts/model.pkl` | Path to the trained model file |
| `APP_PORT` | `3000` | Port the FastAPI app listens on |
| `MODEL_NAME` | `baseline-v1` | Name used in the MLflow Model Registry |

---

## 7. Dependencies

The application dependencies are declared in both `app/requirements.txt` and `app/pyproject.toml`.

| Package | Version | Purpose |
|---|---|---|
| `fastapi` | 0.111.0 | HTTP framework for the serving layer |
| `uvicorn[standard]` | 0.29.0 | ASGI server that runs the FastAPI app |
| `pandas` | 2.2.2 | Data loading and manipulation in pipeline stages |
| `scikit-learn` | 1.4.2 | StandardScaler, OneHotEncoder, train_test_split, metrics |
| `numpy` | 1.26.4 | Numerical operations |
| `pydantic` | 2.7.1 | Request/response validation in FastAPI |
| `python-dotenv` | 1.0.1 | Loading environment variables from `.env` files |
| `httpx` | 0.27.0 | Async HTTP client |
| `evidently` | 0.4.30 | Data drift detection |
| `whylogs` | 1.3.27 | Per-request prediction profiling |

Optional tools (installed separately): `mlflow`, `feast`, `prefect`, `joblib`.

---

## 8. Data Flow — End to End

This section traces a single piece of data from its raw form to a live prediction.

```
1. Raw CSV (ml/data/raw/dataset.csv)
        │
        ▼
2. prepare.py
   - Drop nulls
   - Normalise column names
        │
        ▼
3. features.py
   - StandardScaler on numeric columns
   - OneHotEncoder on categorical columns
        │
        ▼
4. split.py
   - 80% → train.csv
   - 20% → test.csv  (never seen during training)
        │
        ▼
5. training_flow.py (Metaflow)
   - Trains RandomForest on train.csv
   - Saves model.pkl
        │
        ▼
6. evaluate.py
   - Loads model.pkl
   - Runs predictions on test.csv
   - Writes eval_metrics.json
        │
        ▼
7. deploy_mlflow.sh
   - Reads eval_metrics.json
   - If accuracy ≥ 0.75 AND f1 ≥ 0.70 → promote to Production
        │
        ▼
8. FastAPI /predict endpoint
   - Loads model.pkl at startup
   - Accepts feature_1, feature_2, feature_3
   - Returns prediction + probabilities
```

---

## 9. Quality Gates

Quality gates are the automated checkpoints that decide whether a newly trained model is good enough to serve production traffic.

They are evaluated in `evaluate.py` and re-read by several downstream tools:

```
evaluate.py writes eval_metrics.json
        │
        ├──▶ deploy_mlflow.sh        (promotes to Production if passed=true)
        ├──▶ Airflow DAG             (routes to register_model or skip task)
        ├──▶ GET /metrics/summary    (shows current gate status over HTTP)
        └──▶ POST /retrain response  (shows updated results after retraining)
```

The thresholds are intentionally externalised to environment variables (`MLOPS_MIN_ACCURACY`, `MLOPS_MIN_F1`) so they can be adjusted per environment (e.g., stricter in production, looser in a staging experiment) without changing code.

---

## 10. Running the Application

### Prerequisites

- Python 3.11 or later
- A trained model at `ml/models/artifacts/model.pkl`
- The processed dataset at the path configured in `ml/configs/params.yaml`

### Install dependencies

```bash
cd app
pip install -r requirements.txt
```

### Run the full pipeline (DVC)

This runs all four pipeline stages in order and trains the model:

```bash
bash ml/pipelines/dvc/run_dvc.sh
```

### Start the API server

```bash
uvicorn app.src.main:app --host 0.0.0.0 --port 3000 --reload
```

### Verify the app is running

```bash
# Liveness
curl http://localhost:3000/health

# Readiness (503 if model not loaded)
curl http://localhost:3000/ready

# Make a prediction
curl -X POST http://localhost:3000/predict \
     -H "Content-Type: application/json" \
     -d '{"feature_1": 0.5, "feature_2": -0.3, "feature_3": 7.2}'

# Check all tool statuses
curl http://localhost:3000/tools/status

# Interactive API docs
open http://localhost:3000/docs
```

### Trigger retraining manually

```bash
curl -X POST http://localhost:3000/retrain
# Wait ~30 seconds, then check:
curl http://localhost:3000/metrics/summary
```

### Run individual pipeline stages

```bash
python app/src/prepare.py
python app/src/features.py
python app/src/split.py
python app/src/evaluate.py
```

---

*This documentation reflects the codebase as of the date this file was generated. For the most current configuration options, refer to `ml/configs/params.yaml` and the inline comments in each source file.*