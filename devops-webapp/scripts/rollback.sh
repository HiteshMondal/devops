#!/bin/bash

set -e

echo "Rolling back deployment..."

kubectl rollout undo deployment/devops-webapp

kubectl rollout status deployment/devops-webapp

echo "Rollback complete!"