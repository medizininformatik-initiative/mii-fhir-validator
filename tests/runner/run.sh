#!/bin/bash
# Synthetic tests for scripts/test/validate-test-resources.sh. A fake curl on PATH returns
# canned responses, so no validator, network or terminology server is needed.

set -u

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runner="$repo_dir/scripts/test/validate-test-resources.sh"
input="$repo_dir/.github/test-resources/valid-observation.json"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'EOF'
#!/bin/bash
# Fake curl: writes $FAKE_BODY to the -o file, prints $FAKE_STATUS for -w, exits $FAKE_EXIT.
out=""
while [[ $# -gt 0 ]]; do
  [[ "$1" == "-o" ]] && { out="$2"; shift; }
  shift
done
[[ "${FAKE_EXIT:-0}" -ne 0 ]] && exit "$FAKE_EXIT"
printf '%s' "${FAKE_BODY:-}" > "$out"
printf '%s' "${FAKE_STATUS:-200}"
EOF
chmod +x "$work/bin/curl"

passed=0
failed=0

# case <name> <expected exit> <body> [status] [curl exit] [file]
case_() {
  local name="$1" want="$2" body="$3" status="${4:-200}" cexit="${5:-0}" file="${6:-$input}"
  FAKE_BODY="$body" FAKE_STATUS="$status" FAKE_EXIT="$cexit" PATH="$work/bin:$PATH" \
    OUT_DIR="$work/out-$passed-$failed" "$runner" "$file" >"$work/log" 2>&1
  local got=$?
  if [[ "$got" == "$want" ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $name (expected exit $want, got $got)"
    sed 's/^/    /' "$work/log"
  fi
}

ok_info='{"resourceType":"OperationOutcome","issue":[{"severity":"information","code":"informational"}]}'
ok_warn='{"resourceType":"OperationOutcome","issue":[{"severity":"warning","code":"invariant"}]}'
err='{"resourceType":"OperationOutcome","issue":[{"severity":"warning"},{"severity":"error","code":"invalid"}]}'
fatal='{"resourceType":"OperationOutcome","issue":[{"severity":"fatal","code":"exception"}]}'

case_ "information only passes"        0 "$ok_info"
case_ "warning only passes"            0 "$ok_warn"
case_ "error issue fails"              1 "$err"
case_ "fatal issue fails"              1 "$fatal"
case_ "missing issue fails"            1 '{"resourceType":"OperationOutcome"}'
case_ "empty issue array fails"        1 '{"resourceType":"OperationOutcome","issue":[]}'
case_ "issue as string fails"          1 '{"resourceType":"OperationOutcome","issue":"error"}'
case_ "issue entry as string fails"    1 '{"resourceType":"OperationOutcome","issue":["error"]}'
case_ "issue without severity fails"   1 '{"resourceType":"OperationOutcome","issue":[{"code":"x"}]}'
case_ "misspelled severity fails"      1 '{"resourceType":"OperationOutcome","issue":[{"severity":"erorr"}]}'
case_ "upper-case severity fails"      1 '{"resourceType":"OperationOutcome","issue":[{"severity":"ERROR"}]}'
case_ "numeric severity fails"         1 '{"resourceType":"OperationOutcome","issue":[{"severity":2}]}'
case_ "empty severity fails"           1 '{"resourceType":"OperationOutcome","issue":[{"severity":""}]}'
case_ "null severity fails"            1 '{"resourceType":"OperationOutcome","issue":[{"severity":null}]}'
case_ "padded severity fails"          1 '{"resourceType":"OperationOutcome","issue":[{"severity":" error"}]}'
case_ "unknown among valid fails"      1 '{"resourceType":"OperationOutcome","issue":[{"severity":"warning"},{"severity":"critical"}]}'
case_ "all four codes, no error"       1 '{"resourceType":"OperationOutcome","issue":[{"severity":"information"},{"severity":"warning"},{"severity":"error"},{"severity":"fatal"}]}'
case_ "other resource type fails"      1 '{"resourceType":"Bundle"}'
case_ "JSON array fails"               1 '[]'
case_ "non-JSON body fails"            1 '<html>Bad Gateway</html>'
case_ "empty body fails"               1 ''
case_ "HTTP 500 fails"                 1 "$ok_info" 500
case_ "HTTP 404 fails"                 1 "$ok_info" 404
case_ "connection refused fails"       1 "" 200 7
case_ "timeout fails"                  1 "" 200 28
case_ "missing input file fails"       1 "$ok_info" 200 0 "$work/does-not-exist.json"
printf 'not json' > "$work/bad-input.json"
case_ "invalid input JSON fails"       1 "$ok_info" 200 0 "$work/bad-input.json"

VALIDATOR_TIMEOUT=abc "$runner" "$input" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then passed=$((passed + 1)); else failed=$((failed + 1)); echo "FAIL: invalid VALIDATOR_TIMEOUT"; fi

# Each run without OUT_DIR gets its own result directory.
d1="$(FAKE_BODY="$ok_info" PATH="$work/bin:$PATH" TMPDIR="$work" "$runner" "$input" | sed -n 's/.*OperationOutcomes in \(.*\))$/\1/p')"
d2="$(FAKE_BODY="$ok_info" PATH="$work/bin:$PATH" TMPDIR="$work" "$runner" "$input" | sed -n 's/.*OperationOutcomes in \(.*\))$/\1/p')"
if [[ -n "$d1" && -d "$d1" && "$d1" != "$d2" ]]; then passed=$((passed + 1)); else failed=$((failed + 1)); echo "FAIL: isolated result directories ($d1 vs $d2)"; fi

echo "runner: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
