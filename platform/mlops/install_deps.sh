#!/usr/bin/env bash
set -euo pipefail

echo "Installing Python dependencies..."
pip install --upgrade pip
pip install -r app/requirements.txt

echo "Installing DVC..."
pip install dvc

echo "Installing Metaflow..."
pip install metaflow

echo "Installing Prefect..."
pip install prefect

echo "All MLOps dependencies installed."