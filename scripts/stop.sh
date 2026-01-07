#!/bin/bash

# Stop FHIR Validator Service
set -e

echo "Stopping FHIR Validator Service..."

docker-compose down

echo "✓ Services stopped successfully!"
