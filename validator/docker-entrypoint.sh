#!/bin/sh
set -eu

FHIR_SETTINGS_ARG=""

# If TX_SERVER is set and uses plain HTTP, generate fhir-settings.json on the fly
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