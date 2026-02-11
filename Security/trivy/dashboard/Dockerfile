# /Security/trivy/dashboard/Dockerfile

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY trivy-exporter.py .

RUN useradd -m exporter
USER exporter

EXPOSE 8080

CMD ["python", "trivy-exporter.py"]
