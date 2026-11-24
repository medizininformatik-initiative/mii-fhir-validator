#!/bin/bash
# Checks how a running validator reports a wrong Coding.display (#27): as an error (default) or
# as a warning (DISPLAY_ISSUES_ARE_WARNINGS=true). Used by .github/workflows/ci-blaze.yml.
#
# Usage: check-display-mode.sh error|warning
# Env:   VALIDATOR_URL      default http://localhost:8080
#        VALIDATOR_TIMEOUT  max seconds for the request, default 300
# Exit:  0 as expected, 1 not as expected, 2 usage or missing prerequisite

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
resource="$script_dir/../../.github/test-resources/display/observation-wrong-display.json"
url="${VALIDATOR_URL:-http://localhost:8080}"
timeout="${VALIDATOR_TIMEOUT:-300}"
path='Observation.code.coding[0].display'

mode="${1:-}"
if [[ $# -ne 1 || ! "$mode" =~ ^(error|warning)$ ]]; then
  echo "Usage: $0 error|warning" >&2
  exit 2
fi
for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Error: $tool is required but not installed." >&2; exit 2; }
done
[[ "$timeout" =~ ^[0-9]+$ ]] || { echo "Error: VALIDATOR_TIMEOUT must be a number of seconds." >&2; exit 2; }

fail() { echo "✗ display mode '$mode': $1" >&2; exit 1; }

result="$(mktemp "${TMPDIR:-/tmp}/display-mode.XXXXXX")" || exit 2
trap 'rm -f "$result"' EXIT

status="$(curl -sS -X POST "$url/validateResource" \
  --connect-timeout 10 --max-time "$timeout" \
  -H "Content-Type: application/fhir+json" \
  -H "Accept: application/fhir+json" \
  -o "$result" -w '%{http_code}' \
  --data-binary @"$resource")" || fail "request to $url failed (is the validator running?)"
[[ "$status" =~ ^2[0-9][0-9]$ ]] || fail "HTTP status $status: $(head -c 300 "$result")"
jq -e '.resourceType == "OperationOutcome" and (.issue | type == "array")' "$result" >/dev/null 2>&1 \
  || fail "response is not an OperationOutcome: $(head -c 300 "$result")"

# The display issue: located at the display element, text "Invalid display …".
display_issues="$(jq -c --arg p "$path" '[.issue[]
  | select(((.expression // []) + (.location // [])) | index($p))
  | select((.details.text // "") | startswith("Invalid display"))]' "$result")"
count="$(jq length <<<"$display_issues")"
[[ "$count" -eq 1 ]] || fail "expected 1 'Invalid display' issue at $path, got $count: $(jq -c '[.issue[] | {severity, expression, text: .details.text}]' "$result")"
severity="$(jq -r '.[0].severity' <<<"$display_issues")"
[[ "$severity" == "$mode" ]] || fail "the 'Invalid display' issue has severity '$severity'"

# Everything else in the resource is valid: in error mode the display issue is the only error,
# in warning mode there is none.
errors="$(jq '[.issue[] | select(.severity == "fatal" or .severity == "error")] | length' "$result")"
want=0
[[ "$mode" == error ]] && want=1
[[ "$errors" -eq "$want" ]] || fail "expected $want fatal/error issue(s), got $errors: $(jq -c '[.issue[] | select(.severity == "fatal" or .severity == "error") | {severity, expression, text: .details.text}]' "$result")"

echo "✓ display mode '$mode': 'Invalid display' reported as $severity"
