#!/bin/bash

# Download the latest FHIR validator JAR
# Official validator releases: https://github.com/hapifhir/org.hl7.fhir.core/releases

set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

VALIDATOR_VERSION="${1:-latest}"
DOWNLOAD_URL="https://github.com/hapifhir/org.hl7.fhir.core/releases/latest/download/validator_cli.jar"

if [ "$VALIDATOR_VERSION" != "latest" ]; then
    DOWNLOAD_URL="https://github.com/hapifhir/org.hl7.fhir.core/releases/download/${VALIDATOR_VERSION}/validator_cli.jar"
fi

echo "Downloading FHIR Validator..."
echo "URL: $DOWNLOAD_URL"

curl -L -o "$SCRIPT_DIR/validator_cli.jar" "$DOWNLOAD_URL"

if [ -f "$SCRIPT_DIR/validator_cli.jar" ]; then
    echo "✓ Download complete!"
    echo "✓ File: $SCRIPT_DIR/validator_cli.jar"
    ls -lh "$SCRIPT_DIR/validator_cli.jar"
    
    # Test the JAR by checking help output
    echo ""
    echo "Testing validator..."
    if java -jar "$SCRIPT_DIR/validator_cli.jar" -help 2>&1 | grep -q "FHIR Validation"; then
        echo "✓ Validator JAR is valid"
    else
        echo "⚠ Warning: Could not verify validator (but file downloaded successfully)"
    fi
else
    echo "✗ Download failed!"
    exit 1
fi
