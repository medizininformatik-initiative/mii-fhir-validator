#!/bin/bash
# Validates FHIR resources against a running validator and fails on fatal/error issues.
# Used by .github/workflows/ci-blaze.yml and `make test`.
#
# Usage: validate-test-resources.sh [FILE ...]   (default: .github/test-resources/*.json)
# Env:   VALIDATOR_URL      default http://localhost:8080
#        VALIDATOR_TIMEOUT  max seconds per request, default 300
#        OUT_DIR            where OperationOutcomes are written; default: a new temp directory
# Exit:  0 all passed, 1 at least one resource failed, 2 usage or missing prerequisite

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
url="${VALIDATOR_URL:-http://localhost:8080}"
timeout="${VALIDATOR_TIMEOUT:-300}"

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Error: $tool is required but not installed." >&2; exit 2; }
done
[[ "$timeout" =~ ^[0-9]+$ ]] || { echo "Error: VALIDATOR_TIMEOUT must be a number of seconds." >&2; exit 2; }

if [[ $# -eq 0 ]]; then
  set -- "$repo_dir"/.github/test-resources/*.json
fi

if [[ -n "${OUT_DIR:-}" ]]; then
  out_dir="$OUT_DIR"
  mkdir -p "$out_dir" || exit 2
else
  out_dir="$(mktemp -d "${TMPDIR:-/tmp}/mii-fhir-validator-results.XXXXXX")" || exit 2
fi

passed=0
failed=0

fail() { # file message
  echo "✗ $1: $2"
  failed=$((failed + 1))
}

for file in "$@"; do
  echo "Testing: $file"
  if [[ ! -f "$file" ]]; then
    fail "$file" "file not found"
    continue
  fi
  if ! jq -e . "$file" >/dev/null 2>&1; then
    fail "$file" "input is not valid JSON"
    continue
  fi

  name="$(basename "$file" .json)"
  result="$out_dir/OperationOutcome-$name.json"
  n=1
  while [[ -e "$result" ]]; do
    n=$((n + 1))
    result="$out_dir/OperationOutcome-$name-$n.json"
  done

  status="$(curl -sS -X POST "$url/validateResource" \
    --connect-timeout 10 --max-time "$timeout" \
    -H "Content-Type: application/fhir+json" \
    -H "Accept: application/fhir+json" \
    -o "$result" -w '%{http_code}' \
    --data-binary @"$file")"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    fail "$file" "request to $url failed (curl exit $rc; is the validator running?)"
    continue
  fi
  if [[ ! "$status" =~ ^2[0-9][0-9]$ ]]; then
    fail "$file" "HTTP status $status, see $result"
    continue
  fi
  if ! jq -e 'type == "object" and .resourceType == "OperationOutcome"' "$result" >/dev/null 2>&1; then
    fail "$file" "response is not an OperationOutcome, see $result"
    continue
  fi
  if ! jq -e '(.issue | type == "array") and (.issue | length > 0) and all(.issue[]; type == "object")' "$result" >/dev/null 2>&1; then
    fail "$file" "OperationOutcome.issue is missing or malformed, see $result"
    continue
  fi
  # FHIR R4 IssueSeverity: fatal | error | warning | information. Anything else is a failure.
  if ! jq -e 'all(.issue[]; .severity | IN("fatal", "error", "warning", "information"))' "$result" >/dev/null 2>&1; then
    unknown="$(jq -c '[.issue[].severity | select(IN("fatal", "error", "warning", "information") | not)] | unique' "$result" 2>/dev/null)"
    fail "$file" "unknown issue severity ${unknown:-?}, see $result"
    continue
  fi

  errors="$(jq '[.issue[] | select(.severity == "fatal" or .severity == "error")] | length' "$result")"
  if [[ ! "$errors" =~ ^[0-9]+$ ]]; then
    fail "$file" "could not count issues, see $result"
  elif [[ "$errors" -gt 0 ]]; then
    fail "$file" "$errors fatal/error issue(s), see $result"
  else
    echo "✓ $file"
    passed=$((passed + 1))
  fi
done

echo
echo "Results: $passed passed, $failed failed (OperationOutcomes in $out_dir)"
[[ "$failed" -eq 0 ]]
