#!/bin/bash
# Tests for validator/docker-entrypoint.sh: configuration errors (exit status and message),
# proxy and fhir-settings.json handling, java argument construction, package cache modes and
# the supervision of nginx and the validator (signals, unexpected exits, exit codes).
# Stubs for `java` and `nginx` print their arguments instead of starting the real programs, so
# no terminology server, SNOMED CT or IG packages are needed. FAKE_JAVA / FAKE_NGINX select
# what the stub does after starting (see the stubs below).
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
# FAKE_JAVA: stop (default) sends TERM to PID 1 like `docker stop` once the server is up;
#   exit crashes after 1 s with FAKE_JAVA_EXIT; ignore-term is like stop but ignores the
#   forwarded TERM; run keeps running until it is signalled.
cat > "$work/fake/java" <<'EOF'
#!/bin/sh
trap 'echo "JAVA: got TERM"; exit 143' TERM
echo "JAVA_TOOL_OPTIONS=$JAVA_TOOL_OPTIONS"
for a in "$@"; do echo "ARG=$a"; done
if [ -f /tmp/fhir-settings.json ]; then echo "SETTINGS:"; cat /tmp/fhir-settings.json; fi
[ "$(cat /tmp/validator.pid 2>/dev/null)" = "$$" ] && echo "PIDFILE=ok"
case "${FAKE_JAVA:-stop}" in
  stop) kill -TERM 1 ;;
  exit) sleep 1; exit "${FAKE_JAVA_EXIT:-0}" ;;
  ignore-term) trap '' TERM; kill -TERM 1 ;;
esac
sleep 30 & wait $!
EOF
# FAKE_NGINX: run (default) keeps running until it is signalled; exit ends after 1 s with
#   FAKE_NGINX_EXIT. `nginx -t` exits with FAKE_NGINX_TEST_EXIT (default 0).
cat > "$work/fake/nginx" <<'EOF'
#!/bin/sh
trap 'echo "NGINX: got TERM"; exit 0' TERM
for a in "$@"; do echo "NGINX_ARG=$a"; done
case " $* " in *" -t "*) exit "${FAKE_NGINX_TEST_EXIT:-0}" ;; esac
case "${FAKE_NGINX:-run}" in
  exit) sleep 1; exit "${FAKE_NGINX_EXIT:-0}" ;;
esac
sleep 30 & wait $!
EOF
chmod 755 "$work/fake/java" "$work/fake/nginx"
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
    [[ "$p" == ARG=* || "$p" == NGINX_ARG=* ]] && mode=-qxF # one argument per line: match it exactly
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
display_err="Error: DISPLAY_ISSUES_ARE_WARNINGS must be true or false."
run "DISPLAY_ISSUES_ARE_WARNINGS=yes" 1 -e DISPLAY_ISSUES_ARE_WARNINGS=yes -- "+$display_err" "-ARG=server"
run "DISPLAY_ISSUES_ARE_WARNINGS=TRUE" 1 -e DISPLAY_ISSUES_ARE_WARNINGS=TRUE -- "+$display_err" "-ARG=server"
additional_err='Error: ADDITIONAL_IG_PARAMS must be a list of "-ig <package#version|path>" pairs.'
run "ADDITIONAL_IG_PARAMS without -ig" 1 -e "ADDITIONAL_IG_PARAMS=extra.pkg#5.0.0" -- "+$additional_err" "-ARG=server"
run "ADDITIONAL_IG_PARAMS with a lone -ig" 1 -e "ADDITIONAL_IG_PARAMS=-ig extra.pkg#5.0.0 -ig" -- "+$additional_err" "-ARG=server"
run "ADDITIONAL_IG_PARAMS with an option as source" 1 -e "ADDITIONAL_IG_PARAMS=-ig -tx" -- "+$additional_err" "-ARG=server"
run "ADDITIONAL_IG_PARAMS with -allowNetworkAccess as source" 1 \
  -e "ADDITIONAL_IG_PARAMS=-ig extra.pkg#5.0.0 -ig -allowNetworkAccess" -- "+$additional_err" "-ARG=server"
run "ADDITIONAL_IG_PARAMS with a ./ path" 0 -e "ADDITIONAL_IG_PARAMS=-ig ./-name.tgz" -- "+ARG=./-name.tgz"

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

# Java arguments: the validator listens on loopback port 8081 only; nginx owns port 8080.
run "default arguments" 0 -- "+ARG=-Xmx16g" "+ARG=server" "+ARG=8081" "-ARG=8080" "-ARG=-allowNetworkAccess" \
  "+ARG=4.0" "+ARG=/tmp/tx-cache" "+ARG=default.pkg#1.0.0" "+ARG=/app/validator/advisor.json" "-ARG=-txLog" \
  "-ARG=-display-issues-are-warnings" "+PIDFILE=ok"
run "DISPLAY_ISSUES_ARE_WARNINGS=true" 0 -e DISPLAY_ISSUES_ARE_WARNINGS=true -- "+ARG=-display-issues-are-warnings"
run "DISPLAY_ISSUES_ARE_WARNINGS=false" 0 -e DISPLAY_ISSUES_ARE_WARNINGS=false -- "-ARG=-display-issues-are-warnings" "+ARG=server"
run "DISPLAY_ISSUES_ARE_WARNINGS empty" 0 -e DISPLAY_ISSUES_ARE_WARNINGS= -- "-ARG=-display-issues-are-warnings" "+ARG=server"
run "IG_PARAMS replaces the defaults" 0 -e "IG_PARAMS=-ig custom.pkg#2.0.0 -ig /igs/local.tgz" -- \
  "+ARG=custom.pkg#2.0.0" "+ARG=/igs/local.tgz" "-ARG=default.pkg#1.0.0"
run "ADDITIONAL_IG_PARAMS extends the defaults" 0 -e "ADDITIONAL_IG_PARAMS=-ig extra.pkg#5.0.0" -- \
  "+ARG=default.pkg#1.0.0" "+ARG=extra.pkg#5.0.0"
run "ADDITIONAL_IG_PARAMS extends IG_PARAMS" 0 -e "IG_PARAMS=-ig a.pkg#1.0.0" \
  -e "ADDITIONAL_IG_PARAMS=-ig b.pkg#2.0.0 -ig /igs/c.tgz" -- \
  "+ARG=a.pkg#1.0.0" "+ARG=b.pkg#2.0.0" "+ARG=/igs/c.tgz" "-ARG=default.pkg#1.0.0"
run "ADDITIONAL_IG_PARAMS empty" 0 -e ADDITIONAL_IG_PARAMS= -- "+ARG=default.pkg#1.0.0" "+ARG=server"
run "JAVA_OPTS, FHIR_VERSION, TX_CACHE_DIR, TX_LOG" 0 -e JAVA_OPTS=-Xmx2g -e FHIR_VERSION=5.0 \
  -e TX_CACHE_DIR=/tmp/other -e TX_LOG=/tmp/other/tx.log -- \
  "+ARG=-Xmx2g" "-ARG=-Xmx16g" "+ARG=5.0" "+ARG=/tmp/other" "+ARG=-txLog" "+ARG=/tmp/other/tx.log"

# nginx and supervision. A normal stop (TERM to PID 1) stops both children and exits 0; an
# unexpected exit of either child stops the other and fails with its code (0 becomes 1).
run "nginx config is tested, then started" 0 -- "+NGINX_ARG=-t" "+NGINX_ARG=-c" \
  "+NGINX_ARG=/app/validator/nginx.conf" "+NGINX_ARG=-e" "+NGINX_ARG=stderr"
run "SIGTERM stops both and exits 0" 0 -- "+JAVA: got TERM" "+NGINX: got TERM" "-Error"
run "validator exit status is passed through" 3 -e FAKE_JAVA=exit -e FAKE_JAVA_EXIT=3 -- \
  "+Error: validator exited unexpectedly with code 3" "+NGINX: got TERM"
run "validator exit 0 is a failure" 1 -e FAKE_JAVA=exit -e FAKE_JAVA_EXIT=0 -- \
  "+Error: validator exited unexpectedly with code 0" "+NGINX: got TERM"
run "nginx exit status is passed through" 2 -e FAKE_JAVA=run -e FAKE_NGINX=exit -e FAKE_NGINX_EXIT=2 -- \
  "+Error: nginx exited unexpectedly with code 2" "+JAVA: got TERM"
run "nginx exit 0 is a failure" 1 -e FAKE_JAVA=run -e FAKE_NGINX=exit -e FAKE_NGINX_EXIT=0 -- \
  "+Error: nginx exited unexpectedly with code 0" "+JAVA: got TERM"
run "nginx config test failure" 1 -e FAKE_NGINX_TEST_EXIT=1 -- \
  "+Error: nginx configuration test failed" "-ARG=server"
run "child ignoring TERM is killed after the grace period" 0 -e FAKE_JAVA=ignore-term -- \
  "+NGINX: got TERM" "+Warning: still running after 8 s; sending KILL."

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
run "read-only root filesystem" 0 --read-only --tmpfs /tmp -e FHIR_HOME=/var/lib/fhir -- \
  "+using baked-in read-only cache" "+-Duser.home=/app/fhir-cache"
run "read-only root without writable /tmp" 1 --read-only -e FHIR_HOME=/var/lib/fhir -- \
  "+Error: /tmp must be writable" "-ARG=server" "-NGINX_ARG=-t"
h="$(home)"
run "FHIR_CACHE_SEED=false starts blank" 0 -v "$h:/data" -e FHIR_HOME=/data -e FHIR_CACHE_SEED=false -- \
  "-Seeded" "-baked-in" "+-Duser.home=/data"

echo "entrypoint ($image): $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
