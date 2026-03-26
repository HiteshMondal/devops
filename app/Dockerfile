# app/Dockerfile
# Multi-stage build — keeps the final image lean
# Compatible with Docker and Podman

# Stage 1: dependency builder
FROM python:3.11-slim AS builder

WORKDIR /build

# System deps needed to compile any C-extension wheels
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN pip install --upgrade pip \
    && pip install --prefix=/install --no-cache-dir -r requirements.txt

# Stage 2: runtime image
FROM python:3.11-slim AS runtime

# Non-root user for security
RUN groupadd --gid 1001 appgroup \
    && useradd  --uid 1001 --gid appgroup --shell /bin/bash --create-home appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY src/ ./src/

# Switch to non-root
USER appuser

# Environment defaults (overridden by Kubernetes ConfigMap / Secrets)
ENV APP_NAME=devops-aiml-app \
    APP_PORT=3000 \
    APP_ENV=production \
    MODEL_NAME=baseline-v1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

EXPOSE 3000

# Healthcheck (mirrors Kubernetes probe)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:3000/health')"

# Production server — single worker per container (scale via Kubernetes replicas)
CMD ["uvicorn", "src.main:app", \
     "--host", "0.0.0.0", \
     "--port", "3000", \
     "--workers", "1", \
     "--log-level", "info"]