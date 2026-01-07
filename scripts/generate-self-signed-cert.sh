#!/bin/bash

# Generate self-signed certificate for internal nginx HTTPS
# This is needed because the FHIR validator forces HTTPS connections

CERT_DIR="nginx/certs"
CERT_FILE="${CERT_DIR}/self-signed.crt"
KEY_FILE="${CERT_DIR}/self-signed.key"

# Check if certificates already exist
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo "✓ Self-signed certificates already exist"
    exit 0
fi

echo "Generating self-signed certificate for internal HTTPS..."

# Create certs directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Generate certificate with Subject Alternative Names (required for modern SSL)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/CN=nginx" \
    -addext "subjectAltName=DNS:nginx,DNS:localhost" \
    2>/dev/null

if [ $? -eq 0 ]; then
    echo "✓ Self-signed certificate generated successfully"
    echo "  Certificate: $CERT_FILE"
    echo "  Private key: $KEY_FILE"
else
    echo "✗ Failed to generate certificate"
    exit 1
fi
