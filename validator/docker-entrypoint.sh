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

# Report a wrong Coding.display as a warning instead of an error (#27). Codes, ValueSet
# membership and missing code systems are still errors.
case "${DISPLAY_ISSUES_ARE_WARNINGS:-false}" in
  true) DISPLAY_ARG="-display-issues-are-warnings" ;;
  false) DISPLAY_ARG="" ;;
  *)
    echo "Error: DISPLAY_ISSUES_ARE_WARNINGS must be true or false." >&2
    exit 1
    ;;
esac

# IGs loaded in addition to IG_PARAMS or the image defaults (#29): only "-ig <source>" pairs,
# so a package without -ig, or an option such as -tx in place of a source, fails here instead
# of reaching the validator. A file whose name starts with "-" needs a path: -ig ./-name.tgz
ig_pairs() { # ig_pairs <word>...: true if the words alternate "-ig <source>", source not "-…"
  while [ "$#" -gt 0 ]; do
    [ "$1" = "-ig" ] && [ "$#" -ge 2 ] || return 1
    case "$2" in -*) return 1 ;; esac
    shift 2
  done
}
# shellcheck disable=SC2086  # split into words like on the java command line below
if [ -n "${ADDITIONAL_IG_PARAMS:-}" ] && ! ig_pairs $ADDITIONAL_IG_PARAMS; then
  echo 'Error: ADDITIONAL_IG_PARAMS must be a list of "-ig <package#version|path>" pairs.' >&2
  exit 1
fi

# May TX_SERVER resolve to a private address (#26)? Default true: the compose profiles and most
# cluster deployments reach the terminology server on a private network. false keeps the
# validator's private-address blocking (6.10+ SSRF protection) for the configured server too.
case "${TX_SERVER_ALLOW_PRIVATE_NETWORK:-true}" in
  true | false) ALLOW_PRIVATE_NETWORK="${TX_SERVER_ALLOW_PRIVATE_NETWORK:-true}" ;;
  *)
    echo "Error: TX_SERVER_ALLOW_PRIVATE_NETWORK must be true or false." >&2
    exit 1
    ;;
esac

# nginx temporary files, the PID files and fhir-settings.json live in /tmp.
if ! mkdir -p /tmp/nginx 2>/dev/null || [ ! -w /tmp/nginx ]; then
  echo "Error: /tmp must be writable. With a read-only root filesystem, mount a tmpfs or emptyDir at /tmp." >&2
  exit 1
fi

FHIR_SETTINGS_ARG=""

# fhir-settings.json: one server entry for TX_SERVER when it uses plain http://, has basic auth
# credentials, or may resolve to a private address (validator 6.10+ refuses private addresses
# unless the entry has allowPrivateNetwork; 6.9.11 ignores the key). The validator matches the
# entry by scheme, host, port and path prefix. An explicit -fhir-settings file takes precedence
# over fhir.settings.path and ~/.fhir/fhir-settings.json.
if [ -n "${TX_SERVER:-}" ]; then
  allow_http=false
  case "$TX_SERVER" in http://*) allow_http=true ;; esac
  if [ "$allow_http" = true ] || [ -n "${TX_SERVER_USERNAME:-}" ] || [ "$ALLOW_PRIVATE_NETWORK" = true ]; then
    {
      printf '{\n  "servers": [\n    {\n'
      printf '      "url": "%s",\n      "type": "fhir",\n' "$TX_SERVER"
      if [ -n "${TX_SERVER_USERNAME:-}" ]; then # the pair check above guarantees the password
        printf '      "authenticationType": "basic",\n'
        printf '      "username": "%s",\n      "password": "%s"' "$TX_SERVER_USERNAME" "$TX_SERVER_PASSWORD"
      else
        printf '      "authenticationType": "none"'
      fi
      if [ "$allow_http" = true ]; then printf ',\n      "allowHttp": true'; fi
      if [ "$ALLOW_PRIVATE_NETWORK" = true ]; then printf ',\n      "allowPrivateNetwork": true'; fi
      printf '\n    }\n  ]\n}\n'
    } > /tmp/fhir-settings.json
    FHIR_SETTINGS_ARG="-fhir-settings /tmp/fhir-settings.json"
  fi
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
# shellcheck disable=SC2086  # intentional word-splitting on IG_PARAMS, ADDITIONAL_IG_PARAMS, FHIR_SETTINGS_ARG, DISPLAY_ARG and TX_LOG
sh -c 'echo "$$" > /tmp/validator.pid && exec "$@"' validator \
  java ${JAVA_OPTS:--Xmx16g} -jar /app/validator_cli.jar \
  server \
  8081 \
  -version ${FHIR_VERSION:-4.0} \
  -txCache ${TX_CACHE_DIR:-/tmp/tx-cache} \
  ${TX_SERVER:+-tx $TX_SERVER} \
  $FHIR_SETTINGS_ARG \
  ${IG_PARAMS:-$DEFAULT_IG_PARAMS} ${ADDITIONAL_IG_PARAMS:-} \
  -authorise-non-conformant-tx-servers \
  -advisor-file /app/validator/advisor.json \
  $DISPLAY_ARG \
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
