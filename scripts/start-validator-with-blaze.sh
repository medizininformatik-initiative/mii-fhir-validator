#!/bin/bash
set -e

# Start validator with Blaze terminology server
echo "Starting FHIR Validator with Blaze terminology server..."

# Check if .env exists, if not copy from .env.default
if [ ! -f .env ]; then
    echo "Creating .env from .env.default..."
    cp .env.default .env
fi

# Verify TX_SERVER is set for Blaze
if ! grep -q "TX_SERVER.*blaze-terminology" .env; then
    echo "⚠️  Warning: TX_SERVER in .env does not point to Blaze."
    echo "   Expected: TX_SERVER=\"http://blaze-terminology:8080/fhir\""
    echo ""
fi

docker compose --profile blaze up -d

echo ""
echo "✓ Services started with Blaze profile"
echo ""
echo "Next steps:"
echo "  1. Wait for Blaze to be ready: docker compose logs -f blaze"
echo "  2. Upload terminology: ./scripts/terminology/upload-terminology.sh"
echo ""
echo "Access points:"
echo "  - Validator API: http://localhost:8080"
echo "  - Blaze server:  http://localhost:8082"
