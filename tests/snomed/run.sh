#!/bin/bash
# Synthetic tests for scripts/ci/download-snomed-ct.sh. A fake curl on PATH serves a real tiny
# zip, an HTML page or a curl error per source, so no network or secret is needed.

set -u

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo_dir/scripts/ci/download-snomed-ct.sh"
file="SnomedCT_InternationalRF2_PRODUCTION_20250701T120000Z.zip"
token="tok-SECRET-123"
key="key-SECRET-456"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v zip >/dev/null 2>&1 || { echo "error: zip is required for tests/snomed"; exit 1; }
mkdir -p "$work/bin" "$work/src"
echo "release" > "$work/src/README.txt"
(cd "$work/src" && zip -q "$work/good.zip" README.txt)

cat > "$work/bin/curl" <<'EOF'
#!/bin/bash
# Fake curl: logs its arguments, then acts on FAKE_SW (speicherwolke) or FAKE_NLM:
# zip = write a valid zip, html = write an HTML page, a number = fail with that exit code.
printf '%s\n' "$*" >> "$FAKE_LOG"
out=""; mode=""
for a in "$@"; do
  [[ "$prev" == "-o" ]] && out="$a"
  [[ "$a" == *speicherwolke* ]] && mode="$FAKE_SW"
  [[ "$a" == *uts-ws* ]] && mode="$FAKE_NLM"
  prev="$a"
done
case "$mode" in
  zip) cp "$FAKE_ZIP" "$out" ;;
  html) printf '<html>Login</html>' > "$out" ;;
  *) exit "${mode:-6}" ;;
esac
EOF
chmod +x "$work/bin/curl"

passed=0
failed=0
n=0

# case_ <name> <expected exit> <FAKE_SW> <FAKE_NLM> [token] [key] [filename]
case_() {
  local name="$1" want="$2" sw="$3" nlm="$4" t="${5-$token}" k="${6-$key}" f="${7-$file}"
  n=$((n + 1)); dir="$work/run$n"; mkdir -p "$dir"
  log="$dir.curl.log"; out="$dir.out"; : > "$log"
  (cd "$dir" && FAKE_SW="$sw" FAKE_NLM="$nlm" FAKE_ZIP="$work/good.zip" FAKE_LOG="$log" \
    SCT_DOWNLOAD_TOKEN="$t" UMLS_API_KEY="$k" PATH="$work/bin:$PATH" "$script" "$f" >"$out" 2>&1)
  local got=$?
  if [[ "$got" == "$want" ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $name (expected exit $want, got $got)"
    sed 's/^/    /' "$out"
  fi
}

# check <name> <condition…>: an extra assertion on the last case.
check() {
  local name="$1"; shift
  if "$@"; then passed=$((passed + 1)); else failed=$((failed + 1)); echo "FAIL: $name"; sed 's/^/    /' "$out"; fi
}
no_leak() { ! grep -qE "$token|$key" "$out"; }
# only_target [name]: the run directory holds exactly that file (or nothing), so no temp file is left.
only_target() { local f=("$dir"/*); [[ "${f[*]##*/}" == "${1:-*}" ]]; }

case_ "speicherwolke works" 0 zip 7
check "  NLM not called" bash -c "! grep -q uts-ws '$log'"
check "  zip is in place, no temp file" only_target "$file"
check "  no secret in output" no_leak

case_ "speicherwolke fails, NLM works" 0 7 zip
check "  NLM release URL derived from the file name" grep -q "url=https://download.nlm.nih.gov/umls/kss/IHTSDO2025/IHTSDO20250701/$file" "$log"
check "  zip is in place, no temp file" only_target "$file"
check "  warning names the source" grep -q "warning: speicherwolke failed (curl exit 7)" "$out"
check "  no secret in output" no_leak

case_ "speicherwolke HTML, NLM works" 0 html zip
check "  zip is in place, no temp file" only_target "$file"

case_ "both fail" 1 28 22
check "  error lists both sources" grep -q "Error: .* (tried: speicherwolke NLM)" "$out"
check "  no file left behind" only_target ""
check "  no secret in output" no_leak

case_ "NLM returns HTML (bad key)" 1 7 html
check "  HTML is rejected and removed" only_target ""

case_ "only NLM configured" 0 zip zip ""
check "  speicherwolke not called" bash -c "! grep -q speicherwolke '$log'"

case_ "only speicherwolke configured, fails" 1 7 zip "$token" ""
check "  NLM not called" bash -c "! grep -q uts-ws '$log'"

case_ "no secrets" 1 zip zip "" ""
check "  says what to set" grep -q "set SCT_DOWNLOAD_TOKEN or UMLS_API_KEY" "$out"
check "  curl not called" test ! -s "$log"

case_ "file name without a date" 1 7 zip "$token" "$key" "snomed.zip"
check "  NLM skipped with a warning" grep -q "cannot derive the NLM release path" "$out"

case_ "missing file name" 2 zip zip "$token" "$key" ""
case_ "file name with a path" 2 zip zip "$token" "$key" "../x.zip"

echo "snomed: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
