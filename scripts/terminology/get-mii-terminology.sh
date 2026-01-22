#!/bin/bash -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to display usage
usage() {
  echo "Usage: $0 {install|update}"
  echo "  install  - Run npm clean-install"
  echo "  update   - Run npm update"
  exit 1
}

# Check if command is provided
if [[ $# -eq 0 ]]; then
  usage
fi

# Change to script directory to ensure npm runs in the correct location
cd "$SCRIPT_DIR"

# Parse command
case "$1" in
  install)
    if [ -f "package-lock.json" ]; then
      echo "Running npm clean-install..."
      npm clean-install
    else
      echo "No package-lock.json found. Running npm install to generate it..."
      npm install
    fi
    ;;
  update)
    echo "Running npm update..."
    npm update
    ;;
  *)
    echo "Error: Unknown command '$1'"
    usage
    ;;
esac