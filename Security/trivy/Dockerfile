# /Security/trivy/Dockerfile

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir prometheus-client==0.20.0

# Create non-root user
RUN useradd --create-home --shell /bin/bash exporter

COPY trivy-exporter.py /app/

USER exporter

EXPOSE 8080

CMD ["python", "/app/trivy-exporter.py"]

