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

# shellcheck disable=SC2086  # intentional word-splitting on IG_PARAMS and FHIR_SETTINGS_ARG
exec java ${JAVA_OPTS:--Xmx4g} -jar /app/validator_cli.jar \
  -server 8080 \
  -version ${FHIR_VERSION:-4.0} \
  ${TX_SERVER:+-tx $TX_SERVER} \
  $FHIR_SETTINGS_ARG \
  ${IG_PARAMS:-$DEFAULT_IG_PARAMS} \
  -authorise-non-conformant-tx-servers \
  -advisor-file /app/validator/advisor.json \
  -verbose