#!/bin/bash
# Downloads a SNOMED CT International release zip into the current directory.
#
# Usage: download-snomed-ct.sh <filename>
#   e.g. download-snomed-ct.sh SnomedCT_InternationalRF2_PRODUCTION_20250701T120000Z.zip
#
# Sources, tried in order; a source is skipped when its secret is unset:
#   1. speicherwolke.uni-leipzig.de share   SCT_DOWNLOAD_TOKEN (share token)
#   2. NLM UTS download API                  UMLS_API_KEY (UTS profile API key)
# Each download goes to a temp file and only replaces <filename> after `unzip -t` accepts it,
# so an HTML error page never ends up in the CI cache. URLs carry the secrets and are never
# printed. Exit 0 on success, 1 when no source delivered the file, 2 on usage errors.

set -uo pipefail

file="${1:-}"
if [[ -z "$file" || "$file" == */* ]]; then
  echo "Usage: $0 <release zip filename, no path>" >&2
  exit 2
fi

# Connect fast, retry transient errors, and abort a transfer that stalls below 10 kB/s for 60 s.
curl_opts=(-fsSL --connect-timeout 30 --retry 2 --retry-connrefused --speed-limit 10000 --speed-time 60)

tmp="$(mktemp "${file}.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT
tried=()

# fetch <source name> <curl args…>: download into $tmp, check it, move it to $file.
fetch() {
  local name="$1"; shift
  tried+=("$name")
  echo "Downloading $file from $name..."
  curl "${curl_opts[@]}" -o "$tmp" "$@"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "warning: $name failed (curl exit $rc)" >&2
  elif ! unzip -tq "$tmp" >/dev/null 2>&1; then
    echo "warning: $name returned something that is not a valid zip (wrong token or key?)" >&2
  else
    mv "$tmp" "$file" && echo "Downloaded $file from $name." && return 0
  fi
  : > "$tmp"
  return 1
}

if [[ -n "${SCT_DOWNLOAD_TOKEN:-}" ]]; then
  fetch speicherwolke "https://speicherwolke.uni-leipzig.de/index.php/s/${SCT_DOWNLOAD_TOKEN}/download/${file}" && exit 0
fi

if [[ -n "${UMLS_API_KEY:-}" ]]; then
  # NLM stores International releases under IHTSDO<yyyy>/IHTSDO<yyyymmdd>/ (2022 onwards).
  if [[ "$file" =~ _(([0-9]{4})[0-9]{4})T ]]; then
    release_url="https://download.nlm.nih.gov/umls/kss/IHTSDO${BASH_REMATCH[2]}/IHTSDO${BASH_REMATCH[1]}/${file}"
    fetch NLM -G https://uts-ws.nlm.nih.gov/download \
      --data-urlencode "url=${release_url}" --data-urlencode "apiKey=${UMLS_API_KEY}" && exit 0
  else
    tried+=(NLM)
    echo "warning: cannot derive the NLM release path from $file (expected _<yyyymmdd>T in the name)" >&2
  fi
fi

if [[ ${#tried[@]} -eq 0 ]]; then
  echo "Error: no SNOMED CT source configured; set SCT_DOWNLOAD_TOKEN or UMLS_API_KEY" >&2
else
  echo "Error: SNOMED CT release $file could not be downloaded (tried: ${tried[*]})" >&2
fi
exit 1
