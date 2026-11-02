#!/bin/bash
# Checks values that must stay identical across files (see AGENTS.md, "Keep in sync"):
#   1. IG packages: validator/Dockerfile IG_LIST = .env.default IG_PARAMS = docs/overview.md table
#   2. Image tag:   both validator services in docker-compose.yml = image refs in README.md, docs/use.md
#   3. Terminology BOM: exact version in scripts/terminology/package.json = docs/overview.md table
#   4. SNOMED CT release name: docker-compose.yml = CI workflows = snomed-ct-release/README.md
# docs/overview.md also pins an image tag for the 2026 IG set on purpose; it is not checked.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
failed=0

ok() { echo "ok:   $1"; }
bad() { echo "FAIL: $1"; failed=1; }

# 1. IG packages (same packages, same versions, same order)
dockerfile_igs="$(awk '/^ARG IG_LIST=/{f=1} f{print} f && /"$/ && !/^ARG IG_LIST=/{exit}' validator/Dockerfile |
  grep -oE -- '-ig [^ "\\]+' | sed 's/^-ig //')"
env_igs="$(grep '^IG_PARAMS=' .env.default | grep -oE -- '-ig [^ "]+' | sed 's/^-ig //')"
docs_igs="$(grep -E '^\| `de\.[^`]+` \| `[^`]+` \|' docs/overview.md | sed -E 's/^\| `([^`]+)` \| `([^`]+)` \|.*/\1#\2/')"

if [[ -z "$dockerfile_igs" ]]; then
  bad "no IG packages found in ARG IG_LIST of validator/Dockerfile"
elif [[ "$dockerfile_igs" != "$env_igs" ]]; then
  bad "IG_LIST (validator/Dockerfile) and IG_PARAMS (.env.default) differ:"
  diff <(echo "$dockerfile_igs") <(echo "$env_igs") | sed 's/^/      /'
else
  ok "IG_LIST = IG_PARAMS ($(wc -l <<<"$dockerfile_igs" | tr -d ' ') packages)"
fi
if [[ "$(sort <<<"$dockerfile_igs")" != "$(sort <<<"$docs_igs")" ]]; then
  bad "IG table in docs/overview.md differs from IG_LIST (< Dockerfile, > docs):"
  diff <(sort <<<"$dockerfile_igs") <(sort <<<"$docs_igs") | sed 's/^/      /'
else
  ok "IG table in docs/overview.md = IG_LIST"
fi

# 2. Image tag
image_re='ghcr\.io/medizininformatik-initiative/mii-fhir-validator:[A-Za-z0-9._-]+'
compose_tags="$(grep -oE "$image_re" docker-compose.yml | sed 's/.*://' | sort -u)"
compose_count="$(grep -cE "$image_re" docker-compose.yml)"
if [[ "$compose_count" -ne 2 || "$(wc -l <<<"$compose_tags" | tr -d ' ')" -ne 1 ]]; then
  bad "docker-compose.yml must reference one image tag in both validator services, found: $(echo $compose_tags) ($compose_count refs)"
else
  ok "docker-compose.yml image tag $compose_tags (both validator services)"
  docs_ok=1
  for f in README.md docs/use.md; do
    other="$(grep -oE "$image_re" "$f" | sed 's/.*://' | sort -u | grep -vxF "$compose_tags")"
    if [[ -n "$other" ]]; then
      bad "$f references image tag(s) $(echo $other), expected $compose_tags"
      docs_ok=0
    fi
  done
  [[ $docs_ok -eq 1 ]] && ok "image refs in README.md and docs/use.md = $compose_tags"
fi

# 3. Terminology BOM
bom_pkg='@mii-termserv/de.medizininformatikinitiative.kerndatensatz.terminology.bill-of-materials'
bom_version="$(jq -r --arg p "$bom_pkg" '.dependencies[$p] // empty' scripts/terminology/package.json)"
docs_bom="$(grep -F "| \`$bom_pkg\` |" docs/overview.md | sed -E 's/.*\| `([^`]+)` \|$/\1/')"
if [[ -z "$bom_version" ]]; then
  bad "BOM dependency missing in scripts/terminology/package.json"
elif [[ ! "$bom_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
  bad "BOM version '$bom_version' in scripts/terminology/package.json is not an exact version"
elif [[ "$bom_version" != "$docs_bom" ]]; then
  bad "BOM version: package.json $bom_version, docs/overview.md '${docs_bom}'"
else
  ok "terminology BOM $bom_version (package.json = docs/overview.md)"
fi

# 4. SNOMED CT release directory name
snomed="$(grep -ohE 'SnomedCT_InternationalRF2_PRODUCTION_[0-9]{8}T[0-9]{6}Z' \
  docker-compose.yml .github/workflows/build.yml .github/workflows/ci-blaze.yml .github/workflows/snomed-cache.yml \
  snomed-ct-release/README.md | sort -u)"
for f in docker-compose.yml .github/workflows/build.yml .github/workflows/ci-blaze.yml .github/workflows/snomed-cache.yml; do
  grep -qE 'SnomedCT_InternationalRF2_PRODUCTION_[0-9]{8}T[0-9]{6}Z' "$f" || bad "$f does not name the SNOMED CT release"
done
if [[ "$(wc -l <<<"$snomed" | tr -d ' ')" -ne 1 ]]; then
  bad "SNOMED CT release names differ: $(echo $snomed)"
else
  ok "SNOMED CT release $snomed"
fi

exit "$failed"
