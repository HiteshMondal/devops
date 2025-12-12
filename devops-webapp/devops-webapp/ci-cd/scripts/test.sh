#!/bin/bash

set -e

echo "Running tests..."

cd app
npm install
npm test

echo "Tests completed successfully!"