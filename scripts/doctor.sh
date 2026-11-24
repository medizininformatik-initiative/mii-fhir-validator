#!/bin/bash
# Reports which prerequisites are present for each layer of checks. Reads no secrets: local
# configuration files are only tested for existence.
# Exit: 1 if a prerequisite of `make check` is missing, else 0.

set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
missing_check=0

row() { printf '  %-4s %-22s %s\n' "$1" "$2" "$3"; }

tool() { # name purpose [required-for-check]
  if command -v "$1" >/dev/null 2>&1; then
    row ok "$1" "$2"
  elif [[ -n "${3:-}" ]]; then
    row MISS "$1" "$2 — not installed"
    missing_check=1
  else
    row warn "$1" "$2 — not installed"
  fi
}

present() { # path purpose
  if [[ -e "$1" ]]; then row ok "$1" "$2"; else row warn "$1" "$2 — missing"; fi
}

echo "make check (lint, check-sync, hook/runner/entrypoint tests):"
tool shellcheck "lint-sh" x
tool hadolint "lint-docker" x
tool actionlint "lint-actions" x
tool jq "hooks, check-sync, tests" x
tool docker "lint-compose, test-entrypoint" x
if docker info >/dev/null 2>&1; then
  row ok "docker daemon" "running"
else
  row MISS "docker daemon" "not running"
  missing_check=1
fi

echo
echo "make test (integration, needs the running stack):"
tool curl "validate-test-resources.sh"
present snomed-ct-release/SnomedCT_InternationalRF2_PRODUCTION_20250701T120000Z "SNOMED CT release for Blaze"
present scripts/terminology/node_modules "MII terminology packages (get-mii-terminology.sh install)"
present .env "local configuration (cp .env.default .env)"
present nginx/certs/client-cert.pem "client certificate, ontoserver profile only"
if curl -s -o /dev/null --max-time 3 "${VALIDATOR_URL:-http://localhost:8080}/validateResource" 2>/dev/null; then
  row ok "validator" "reachable at ${VALIDATOR_URL:-http://localhost:8080}"
else
  row warn "validator" "not reachable at ${VALIDATOR_URL:-http://localhost:8080} (docker compose up -d)"
fi

echo
echo "docs:"
want_node="$(tr -d ' \n' < .nvmrc)"
if command -v node >/dev/null 2>&1; then
  have_node="$(node --version | sed 's/^v//')"
  if [[ "${have_node%%.*}" == "${want_node%%.*}" ]]; then
    row ok node "$have_node (.nvmrc: $want_node)"
  else
    row warn node "$have_node, .nvmrc wants $want_node (nvm use)"
  fi
else
  row warn node "not installed (.nvmrc: $want_node)"
fi
present docs/node_modules "docs dependencies (make docs-install)"

echo
if [[ $missing_check -eq 1 ]]; then
  echo "Some prerequisites of 'make check' are missing (MISS). Without STRICT=1, missing linters are skipped."
  exit 1
fi
echo "All prerequisites of 'make check' are present."
