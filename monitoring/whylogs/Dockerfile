# /monitoring/whylogs/Dockerfile

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY monitoring/whylogs/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY monitoring/whylogs ./monitoring/whylogs
RUN mkdir -p /app/ml/data/processed

CMD ["python", "monitoring/whylogs/profiler.py"]