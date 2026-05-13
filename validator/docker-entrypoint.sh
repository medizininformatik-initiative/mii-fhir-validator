#!/bin/sh

set -eu

# Validate credential environment variables
if { [ -n "${TX_SERVER_USERNAME:-}" ] && [ -z "${TX_SERVER_PASSWORD:-}" ]; } || \
   { [ -z "${TX_SERVER_USERNAME:-}" ] && [ -n "${TX_SERVER_PASSWORD:-}" ]; }; then
  echo "Error: TX_SERVER_USERNAME and TX_SERVER_PASSWORD must either both be set or both be unset." >&2
  exit 1
fi

if { [ -n "${TX_SERVER_USERNAME:-}" ] || [ -n "${TX_SERVER_PASSWORD:-}" ]; } && \
   [ -z "${TX_SERVER:-}" ]; then
  echo "Error: TX_SERVER must be set when TX_SERVER_USERNAME/TX_SERVER_PASSWORD are provided." >&2
  exit 1
fi

FHIR_SETTINGS_ARG=""

# Generate fhir-settings.json if TX_SERVER uses plain HTTP or basic auth credentials are provided
if [ -n "${TX_SERVER_USERNAME:-}" ] && [ -n "${TX_SERVER_PASSWORD:-}" ]; then
  case "${TX_SERVER:-}" in
    http://*)
      cat > /tmp/fhir-settings.json <<EOF
{
  "servers": [
    {
      "url": "${TX_SERVER}",
      "type": "fhir",
      "authenticationType": "basic",
      "username": "${TX_SERVER_USERNAME}",
      "password": "${TX_SERVER_PASSWORD}",
      "allowHttp": true
    }
  ]
}
EOF
      ;;
    *)
      cat > /tmp/fhir-settings.json <<EOF
{
  "servers": [
    {
      "url": "${TX_SERVER}",
      "type": "fhir",
      "authenticationType": "basic",
      "username": "${TX_SERVER_USERNAME}",
      "password": "${TX_SERVER_PASSWORD}"
    }
  ]
}
EOF
      ;;
  esac
  FHIR_SETTINGS_ARG="-fhir-settings /tmp/fhir-settings.json"
else
  case "${TX_SERVER:-}" in
    http://*)
      cat > /tmp/fhir-settings.json <<EOF
{
  "servers": [
    {
      "url": "${TX_SERVER}",
      "type": "fhir",
      "authenticationType": "none",
      "allowHttp": true
    }
  ]
}
EOF
      FHIR_SETTINGS_ARG="-fhir-settings /tmp/fhir-settings.json"
      ;;
  esac
fi

# shellcheck disable=SC2086  # intentional word-splitting on IG_PARAMS, FHIR_SETTINGS_ARG and TX_LOG
exec java ${JAVA_OPTS:--Xmx16g} -jar /app/validator_cli.jar \
  server \
  -allowNetworkAccess \
  8080 \
  -version ${FHIR_VERSION:-4.0} \
  -txCache ${TX_CACHE_DIR:-/tmp/tx-cache} \
  ${TX_SERVER:+-tx $TX_SERVER} \
  $FHIR_SETTINGS_ARG \
  ${IG_PARAMS:-$DEFAULT_IG_PARAMS} \
  -authorise-non-conformant-tx-servers \
  -advisor-file /app/validator/advisor.json \
  -verbose \
  -show-times \
  ${TX_LOG:+-txLog $TX_LOG}