#!/bin/bash
set -e

# Start validator with MII Ontoserver via nginx proxy
echo "Starting FHIR Validator with MII Ontoserver..."

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found."
    echo "   Create .env and set: TX_SERVER=\"https://nginx/fhir\""
    exit 1
fi

# Verify TX_SERVER is set for nginx/ontoserver
if ! grep -q "TX_SERVER.*nginx" .env; then
    echo "⚠️  Warning: TX_SERVER in .env does not point to nginx."
    echo "   Expected: TX_SERVER=\"https://nginx/fhir\""
    echo ""
fi

# Check for client certificates
if [ ! -f nginx/certs/client-cert.pem ] || [ ! -f nginx/certs/client-key.key ]; then
    echo "❌ Error: MII Ontoserver client certificates not found."
    echo "   Required files:"
    echo "     - nginx/certs/client-cert.pem"
    echo "     - nginx/certs/client-key.key"
    echo ""
    echo "   See README.md for certificate setup instructions."
    exit 1
fi

docker compose --profile ontoserver up -d

echo ""
echo "✓ Services started with Ontoserver profile"
echo ""
echo "Access points:"
echo "  - Validator API: http://localhost:8080"
echo "  - Nginx proxy:   http://localhost:8081"
