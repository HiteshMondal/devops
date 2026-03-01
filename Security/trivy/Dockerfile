# /Security/trivy/Dockerfile

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir prometheus-client==0.20.0
RUN useradd -u 1000 --create-home --shell /bin/bash exporter \
    && chown -R exporter:exporter /app
COPY --chown=exporter:exporter trivy-exporter.py /app/
USER exporter
EXPOSE 8082
CMD ["python", "/app/trivy-exporter.py"]
