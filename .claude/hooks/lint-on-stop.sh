#!/bin/sh
# Stop hook: runs `make lint` at the end of a turn as a reminder to fix findings before handing
# over (the agent never commits, so a pre-commit hook would never fire). Exit 2 sends stderr
# back to the agent once; on the second stop it lets the agent finish, so this is a reminder,
# not enforcement. Enforcement is the Checks workflow (`make check STRICT=1`). No tests here.

input=$(cat)

# A previous Stop hook already sent the agent back once; do not loop.
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# Nothing changed in the working tree: nothing to lint.
[ -z "$(git status --porcelain 2>/dev/null)" ] && exit 0

cache="${TMPDIR:-/tmp}/mii-fhir-validator-lint-cache"
mkdir -p "$cache"

if ! out=$(XDG_CACHE_HOME="$cache" make --no-print-directory lint 2>&1); then
  printf 'make lint failed. Fix these findings before handing over:\n\n%s\n' "$out" >&2
  exit 2
fi
exit 0
