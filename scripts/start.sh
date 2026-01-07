#!/bin/bash

# Start FHIR Validator Service
set -e

echo "Starting FHIR Validator Service..."

# Check if validator JAR exists
if [ ! -f "validator/validator_cli.jar" ]; then
    echo "⚠️  Validator JAR not found!"
    echo "Please run: cd validator && ./download-validator.sh"
    exit 1
fi

# Check if certificates exist
if [ ! -f "nginx/certs/client-cert.pem" ] || [ ! -f "nginx/certs/client-key.key" ]; then
    echo "⚠️  Client certificates not found!"
    echo "Please place your certificates in nginx/certs/"
    echo "  - client-cert.pem"
    echo "  - client-key.key"
    exit 1
fi

# Start services
echo "Starting Docker Compose services..."
docker-compose up -d

echo ""
echo "✓ Services started successfully!"
echo ""
echo "Services:"
echo "  - FHIR Validator: http://localhost:8080"
echo "  - Nginx Proxy:    http://localhost:8081"
echo ""
echo "View logs with: docker-compose logs -f"
echo "Stop with:      docker-compose down"
