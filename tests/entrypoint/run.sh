#!/bin/bash
# Tests for validator/docker-entrypoint.sh: configuration errors (exit status and message),
# proxy and fhir-settings.json handling, java argument construction and package cache modes.
# A stub `java` prints its arguments instead of starting the validator, so no terminology
# server, SNOMED CT or IG packages are needed.
#
# Env: ENTRYPOINT_TEST_IMAGE  image to run in. Default ubuntu:24.04 (same /bin/sh as the real
#      image) with the working-tree entrypoint mounted. Set it to a built validator image, e.g.
#      mii-fhir-validator:test, to test the entrypoint baked into that image instead.

set -u

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
image="${ENTRYPOINT_TEST_IMAGE:-ubuntu:24.04}"

command -v docker >/dev/null 2>&1 || { echo "Error: docker is required for the entrypoint tests." >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo "Error: the Docker daemon is not running." >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/fake" "$work/cache/.fhir/packages/example.pkg#1.0.0/package"
echo '{"name":"example.pkg","version":"1.0.0"}' > "$work/cache/.fhir/packages/example.pkg#1.0.0/package/package.json"
cat > "$work/fake/java" <<'EOF'
#!/bin/sh
echo "JAVA_TOOL_OPTIONS=$JAVA_TOOL_OPTIONS"
for a in "$@"; do echo "ARG=$a"; done
if [ -f /tmp/fhir-settings.json ]; then echo "SETTINGS:"; cat /tmp/fhir-settings.json; fi
exit "${FAKE_JAVA_EXIT:-0}"
EOF
chmod 755 "$work/fake/java"
chmod -R a+rX "$work"

mounts=(-v "$work/fake:/fake:ro" -v "$work/cache:/app/fhir-cache:ro")
if [[ -z "${ENTRYPOINT_TEST_IMAGE:-}" ]]; then
  mounts+=(-v "$repo_dir/validator/docker-entrypoint.sh:/app/docker-entrypoint.sh:ro")
fi

passed=0
failed=0

# run <name> <expected exit> [docker args...] -- [+must-contain | -must-not-contain ...]
run() {
  local name="$1" want="$2"
  shift 2
  local args=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do args+=("$1"); shift; done
  shift
  local out rc problems=""
  out="$(docker run --rm --user "$(id -u):$(id -g)" "${mounts[@]}" \
    -e PATH=/fake:/usr/local/bin:/usr/bin:/bin \
    -e DEFAULT_IG_PARAMS="-ig default.pkg#1.0.0" \
    ${args[@]+"${args[@]}"} --entrypoint /bin/sh "$image" /app/docker-entrypoint.sh 2>&1)"
  rc=$?
  [[ "$rc" == "$want" ]] || problems+=" exit $rc (expected $want);"
  local p mode
  for pattern in "$@"; do
    p="${pattern#[+-]}"
    mode=-qF
    [[ "$p" == ARG=* ]] && mode=-qxF # one java argument per line: match it exactly
    case "$pattern" in
      +*) grep "$mode" -- "$p" <<<"$out" || problems+=" missing '$p';" ;;
      -*) grep "$mode" -- "$p" <<<"$out" && problems+=" unexpected '$p';" ;;
    esac
  done
  if [[ -z "$problems" ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $name:$problems"
    sed 's/^/    /' <<<"$out"
  fi
}

home() { # fresh host directory to mount as FHIR_HOME
  local d
  d="$(mktemp -d "$work/home.XXXXXX")"
  chmod 777 "$d"
  echo "$d"
}

pair_proxy="Error: FORWARD_PROXY_HOST and FORWARD_PROXY_PORT must either both be set or both be unset."
pair_tx="Error: TX_SERVER_USERNAME and TX_SERVER_PASSWORD must either both be set or both be unset."

# Configuration errors: exact message and exit status 1, java never started.
run "proxy host without port" 1 -e FORWARD_PROXY_HOST=proxy.example -- "+$pair_proxy" "-ARG=server"
run "proxy port without host" 1 -e FORWARD_PROXY_PORT=3128 -- "+$pair_proxy" "-ARG=server"
run "proxy host with scheme" 1 -e FORWARD_PROXY_HOST=http://proxy.example -e FORWARD_PROXY_PORT=3128 -- \
  "+Error: FORWARD_PROXY_HOST must be a hostname or IP address without a URL scheme or whitespace." "-ARG=server"
run "proxy host with whitespace" 1 -e "FORWARD_PROXY_HOST=proxy example" -e FORWARD_PROXY_PORT=3128 -- \
  "+Error: FORWARD_PROXY_HOST must be a hostname or IP address" "-ARG=server"
run "proxy port not numeric" 1 -e FORWARD_PROXY_HOST=proxy.example -e FORWARD_PROXY_PORT=31a8 -- \
  "+Error: FORWARD_PROXY_PORT must be numeric." "-ARG=server"
run "tx username without password" 1 -e TX_SERVER=https://tx.example/fhir -e TX_SERVER_USERNAME=user -- "+$pair_tx" "-ARG=server"
run "tx password without username" 1 -e TX_SERVER=https://tx.example/fhir -e TX_SERVER_PASSWORD=pw -- "+$pair_tx" "-ARG=server"
run "tx credentials without TX_SERVER" 1 -e TX_SERVER_USERNAME=user -e TX_SERVER_PASSWORD=pw -- \
  "+Error: TX_SERVER must be set when TX_SERVER_USERNAME/TX_SERVER_PASSWORD are provided." "-ARG=server"

# Proxy properties.
run "valid proxy" 0 -e FORWARD_PROXY_HOST=proxy.example -e FORWARD_PROXY_PORT=3128 -- \
  "+-Dhttp.proxyHost=proxy.example" "+-Dhttp.proxyPort=3128" "+-Dhttps.proxyHost=proxy.example" \
  "+-Dhttps.proxyPort=3128" "+-Dhttp.nonProxyHosts=localhost|127.*|[::1]|blaze|blaze-terminology|nginx"
run "custom non-proxy hosts" 0 -e FORWARD_PROXY_HOST=proxy.example -e FORWARD_PROXY_PORT=3128 \
  -e FORWARD_PROXY_NON_PROXY_HOSTS=blaze-terminology -- "+-Dhttp.nonProxyHosts=blaze-terminology "
run "no proxy" 0 -- "-proxyHost"

# Terminology server and fhir-settings.json.
run "no TX_SERVER" 0 -- "-ARG=-tx" "-ARG=-fhir-settings" "-SETTINGS:"
run "http TX_SERVER" 0 -e TX_SERVER=http://tx.example/fhir -- \
  "+ARG=http://tx.example/fhir" "+ARG=-fhir-settings" '+"authenticationType": "none"' '+"allowHttp": true'
run "https TX_SERVER" 0 -e TX_SERVER=https://tx.example/fhir -- "+ARG=https://tx.example/fhir" "-ARG=-fhir-settings"
run "https TX_SERVER with basic auth" 0 -e TX_SERVER=https://tx.example/fhir -e TX_SERVER_USERNAME=user \
  -e TX_SERVER_PASSWORD=pw -- '+"authenticationType": "basic"' '+"username": "user"' '-"allowHttp"'
run "http TX_SERVER with basic auth" 0 -e TX_SERVER=http://tx.example/fhir -e TX_SERVER_USERNAME=user \
  -e TX_SERVER_PASSWORD=pw -- '+"authenticationType": "basic"' '+"allowHttp": true'

# Java arguments.
run "default arguments" 0 -- "+ARG=-Xmx16g" "+ARG=server" "+ARG=-allowNetworkAccess" "+ARG=8080" \
  "+ARG=4.0" "+ARG=/tmp/tx-cache" "+ARG=default.pkg#1.0.0" "+ARG=/app/validator/advisor.json" "-ARG=-txLog"
run "IG_PARAMS replaces the defaults" 0 -e "IG_PARAMS=-ig custom.pkg#2.0.0 -ig /igs/local.tgz" -- \
  "+ARG=custom.pkg#2.0.0" "+ARG=/igs/local.tgz" "-ARG=default.pkg#1.0.0"
run "JAVA_OPTS, FHIR_VERSION, TX_CACHE_DIR, TX_LOG" 0 -e JAVA_OPTS=-Xmx2g -e FHIR_VERSION=5.0 \
  -e TX_CACHE_DIR=/tmp/other -e TX_LOG=/tmp/other/tx.log -- \
  "+ARG=-Xmx2g" "-ARG=-Xmx16g" "+ARG=5.0" "+ARG=/tmp/other" "+ARG=-txLog" "+ARG=/tmp/other/tx.log"
run "java exit status is passed through" 3 -e FAKE_JAVA_EXIT=3 -- "+ARG=server"

# Package cache modes.
h="$(home)"
run "seed empty writable cache" 0 -v "$h:/data" -e FHIR_HOME=/data -- \
  "+Seeded FHIR package cache into /data/.fhir/packages" "+-Duser.home=/data"
if [[ -f "$h/.fhir/packages/example.pkg#1.0.0/package/package.json" ]]; then
  passed=$((passed + 1))
else
  failed=$((failed + 1)); echo "FAIL: seeded cache does not contain the baked-in package"
fi
run "populated cache is not reseeded" 0 -v "$h:/data" -e FHIR_HOME=/data -- \
  "+already populated; skipping seed" "+-Duser.home=/data"
run "read-only FHIR_HOME falls back to baked-in cache" 0 -v "$(home):/data:ro" -e FHIR_HOME=/data -- \
  "+FHIR_HOME not writable; using baked-in read-only cache at /app/fhir-cache" "+-Duser.home=/app/fhir-cache"
run "read-only root filesystem" 0 --read-only -e FHIR_HOME=/var/lib/fhir -- \
  "+using baked-in read-only cache" "+-Duser.home=/app/fhir-cache"
h="$(home)"
run "FHIR_CACHE_SEED=false starts blank" 0 -v "$h:/data" -e FHIR_HOME=/data -e FHIR_CACHE_SEED=false -- \
  "-Seeded" "-baked-in" "+-Duser.home=/data"

echo "entrypoint ($image): $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
