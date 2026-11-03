#!/bin/sh

set -eu

FHIR_HOME="${FHIR_HOME:-/root}"
DEFAULT_CACHE="/app/fhir-cache"
CACHE_HOME="${FHIR_HOME}"

if [ "${FHIR_CACHE_SEED:-true}" = "true" ]; then
  pkgs="${FHIR_HOME}/.fhir/packages"
  if [ ! -e "$pkgs" ] || [ -z "$(ls -A "$pkgs" 2>/dev/null)" ]; then
    if mkdir -p "$pkgs" 2>/dev/null && cp -r /app/fhir-cache/.fhir/packages/. "$pkgs/" 2>/dev/null; then
      echo "Seeded FHIR package cache into ${pkgs}"
    else
      echo "FHIR_HOME not writable; using baked-in read-only cache at ${DEFAULT_CACHE}"
      CACHE_HOME="${DEFAULT_CACHE}"
    fi
  else
    echo "FHIR cache at ${pkgs} already populated; skipping seed"
  fi
fi

FORWARD_PROXY_HOST="${FORWARD_PROXY_HOST:-}"
FORWARD_PROXY_PORT="${FORWARD_PROXY_PORT:-}"
FORWARD_PROXY_NON_PROXY_HOSTS="${FORWARD_PROXY_NON_PROXY_HOSTS:-localhost|127.*|[::1]|blaze|blaze-terminology|nginx|*.local|*.svc|*.cluster.local}"

if { [ -n "$FORWARD_PROXY_HOST" ] && [ -z "$FORWARD_PROXY_PORT" ]; } || \
   { [ -z "$FORWARD_PROXY_HOST" ] && [ -n "$FORWARD_PROXY_PORT" ]; }; then
  echo "Error: FORWARD_PROXY_HOST and FORWARD_PROXY_PORT must either both be set or both be unset." >&2
  exit 1
fi

JAVA_TOOL_OPTIONS="-Duser.home=${CACHE_HOME} ${JAVA_TOOL_OPTIONS:-}"

if [ -n "$FORWARD_PROXY_HOST" ] && [ -n "$FORWARD_PROXY_PORT" ]; then
  case "$FORWARD_PROXY_HOST" in
    *://*|*[[:space:]]*)
      echo "Error: FORWARD_PROXY_HOST must be a hostname or IP address without a URL scheme or whitespace." >&2
      exit 1
      ;;
  esac

  case "$FORWARD_PROXY_PORT" in
    *[!0-9]*)
      echo "Error: FORWARD_PROXY_PORT must be numeric." >&2
      exit 1
      ;;
  esac

  JAVA_TOOL_OPTIONS="-Dhttp.proxyHost=${FORWARD_PROXY_HOST} \
-Dhttp.proxyPort=${FORWARD_PROXY_PORT} \
-Dhttps.proxyHost=${FORWARD_PROXY_HOST} \
-Dhttps.proxyPort=${FORWARD_PROXY_PORT} \
-Dhttp.nonProxyHosts=${FORWARD_PROXY_NON_PROXY_HOSTS} \
${JAVA_TOOL_OPTIONS}"
fi

export JAVA_TOOL_OPTIONS

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

# nginx temporary files, the PID files and fhir-settings.json live in /tmp.
if ! mkdir -p /tmp/nginx 2>/dev/null || [ ! -w /tmp/nginx ]; then
  echo "Error: /tmp must be writable. With a read-only root filesystem, mount a tmpfs or emptyDir at /tmp." >&2
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

# Supervision (#21): nginx on port 8080 is the only exposed listener and forwards an allowlist
# of routes to the validator on 127.0.0.1:8081 (no -allowNetworkAccess: loopback only).
# This script stays PID 1: it forwards TERM/INT to both and stops the other process when one
# exits unexpectedly, so the container never keeps running half-alive.
NGINX_CONF=/app/validator/nginx.conf
SHUTDOWN_GRACE=8 # seconds before KILL; below Docker's default stop timeout of 10 s
nginx_pid=""
java_pid=""

alive() { # alive <pid>...: true while any of them runs (exited children are reaped by `sleep`)
  for p in "$@"; do kill -0 "$p" 2>/dev/null && return 0; done
  return 1
}

stop_children() { # TERM both, KILL whatever still runs after SHUTDOWN_GRACE, reap both
  for p in "$nginx_pid" "$java_pid"; do kill -TERM "$p" 2>/dev/null || true; done
  ticks=$((SHUTDOWN_GRACE * 5))
  while [ "$ticks" -gt 0 ] && alive "$nginx_pid" "$java_pid"; do sleep 0.2; ticks=$((ticks - 1)); done
  if alive "$nginx_pid" "$java_pid"; then
    echo "Warning: still running after ${SHUTDOWN_GRACE} s; sending KILL." >&2
    for p in "$nginx_pid" "$java_pid"; do kill -KILL "$p" 2>/dev/null || true; done
  fi
  for p in "$nginx_pid" "$java_pid"; do wait "$p" 2>/dev/null || true; done
}

trap 'trap "" TERM INT; echo "Stopping nginx and the validator."; stop_children; exit 0' TERM INT

if ! nginx -t -q -e stderr -c "$NGINX_CONF"; then
  echo "Error: nginx configuration test failed ($NGINX_CONF)." >&2
  exit 1
fi
nginx -e stderr -c "$NGINX_CONF" &
nginx_pid=$!

# The wrapper writes its PID before exec'ing java, so /tmp/validator.pid is the java process.
# shellcheck disable=SC2086  # intentional word-splitting on IG_PARAMS, FHIR_SETTINGS_ARG and TX_LOG
sh -c 'echo "$$" > /tmp/validator.pid && exec "$@"' validator \
  java ${JAVA_OPTS:--Xmx16g} -jar /app/validator_cli.jar \
  server \
  8081 \
  -version ${FHIR_VERSION:-4.0} \
  -txCache ${TX_CACHE_DIR:-/tmp/tx-cache} \
  ${TX_SERVER:+-tx $TX_SERVER} \
  $FHIR_SETTINGS_ARG \
  ${IG_PARAMS:-$DEFAULT_IG_PARAMS} \
  -authorise-non-conformant-tx-servers \
  -advisor-file /app/validator/advisor.json \
  -verbose \
  -show-times \
  ${TX_LOG:+-txLog $TX_LOG} &
java_pid=$!

while sleep 1; do
  if ! alive "$java_pid"; then child=validator; pid=$java_pid; break; fi
  if ! alive "$nginx_pid"; then child=nginx; pid=$nginx_pid; break; fi
done
rc=0
wait "$pid" || rc=$?
trap "" TERM INT
echo "Error: $child exited unexpectedly with code $rc; stopping the container." >&2
stop_children
[ "$rc" -ne 0 ] || rc=1
exit "$rc"
