#!/bin/sh
# PreToolUse hook (Bash|Read|Edit|Write|Grep): blocks access to local secrets.
# Exit 2 blocks the call and shows stderr to the agent. Fails closed: missing jq, or input
# without the string field the tool needs (Bash: command; Read/Edit/Write: file_path;
# Grep: optional path/glob), blocks the call.
#
# Blocked:
#   - files: .env and every .env.* except exactly .env.default/.env.example; secrets/; private
#     keys anywhere; certificates under certs/. Commands that only see names or metadata are
#     allowed: ls, test, [, stat, echo, printf, find without -exec, git check-ignore/ls-files/
#     status/log.
#   - values: $TX_SERVER_PASSWORD / $SCT_DOWNLOAD_TOKEN / $UMLS_API_KEY expansions; environment dumps (env,
#     printenv, export -p, set, docker inspect, docker exec … env, docker compose config
#     without -q).
#   - searches that read gitignored files: recursive grep, rg -u/--no-ignore/--hidden and
#     find -exec over the repository root or without a path. Searches limited to
#     subdirectories or files are allowed; the Grep tool skips gitignored files unless a glob
#     matches them.
# Heredoc bodies written by cat/tee are data and are not checked.

hook_lib="$(dirname "$0")/lib"
[ -r "$hook_lib/segments.sh" ] || { echo "Blocked: $hook_lib/segments.sh is missing." >&2; exit 2; }
. "$hook_lib/segments.sh"

command -v jq >/dev/null 2>&1 || {
  echo "Blocked: jq is required by .claude/hooks/block-secret-reads.sh but is not installed." >&2
  exit 2
}

input=$(cat)
malformed() {
  echo "Blocked: block-secret-reads.sh could not read the $1 tool input it needs." >&2
  exit 2
}
tool=$(printf '%s' "$input" | jq -er '.tool_name | strings') || malformed "tool_name and"
case "$tool" in
  Bash) target=$(printf '%s' "$input" | jq -er '.tool_input.command | strings') || malformed Bash ;;
  Read | Edit | Write) target=$(printf '%s' "$input" | jq -er '.tool_input.file_path | strings') || malformed "$tool" ;;
  Grep)
    target=$(printf '%s' "$input" | jq -er '.tool_input | objects | [.path, .glob]
      | if all(.[]; . == null or type == "string") then map(strings) | join("\n") else error("type") end') ||
      malformed Grep
    glob=$(printf '%s' "$input" | jq -r '.tool_input.glob // empty')
    if [ -n "$glob" ]; then
      top="${glob#\*\*/}" # `**/x` also matches x at the top level
      for name in .env .env.local secrets; do
        # shellcheck disable=SC2254 # the glob is matched as a pattern on purpose
        case "$name" in $glob | $top) echo "Blocked by repo policy (Grep glob '$glob' matches $name; globs override gitignore)." >&2; exit 2 ;; esac
      done
    fi
    ;;
  *) malformed "$tool" ;;
esac

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Checks for one normalized segment per line. mode=bash: field 1 is the command; mode=path:
# the whole line is one path. full=0 is the quote-split pass: it runs only the command checks,
# and a search there counts as unsafe only for a path it sees (quotes may cut the paths off).
checks='
function fname(p,  b) {
  sub(/\/+$/, "", p); b = p; sub(/.*\//, "", b)
  if (b ~ /^\.env(\..+)?$/ && b != ".env.default" && b != ".env.example") return "env file " p
  if (p == "secrets" || p ~ /(^|\/)secrets(\/|$)/) return "secrets/ " p
  if (b ~ /\.(key|p12|pfx|jks)$/) return "private key " p
  if (p ~ /(^|\/)certs\/.+\.(pem|crt)$/) return "certificate " p
  return ""
}
function unsafe(p) {  # true if a search starting at p would reach the repository root or secrets
  sub(/\/+$/, "", p)
  if (p == "" || p ~ /^(\.|\.\.|~|\*|\.\*|\$|\$PWD|\$HOME)$/ || p ~ /^(\.\.\/)+\.?\.?$/ || p ~ /^(~|\$HOME|\$PWD)\//) return 1
  if (p ~ /^\// && index(root "/", p "/") == 1) return 1
  if (p ~ /(^|\/)(secrets|certs)$/) return 1
  return 0
}
function search_paths(start,  j, np, havepat, s) {  # grep/rg path operands after options
  np = 0; havepat = 0; s = 0
  for (j = start; j <= n; j++) {
    if (!s && t[j] == "--") { s = 1; continue }
    if (!s && t[j] ~ /^-/) {
      if (t[j] ~ /^(-e|-f|--regexp|--file)$/ || t[j] ~ /^-[A-Za-z]*[ef]$/) { havepat = 1; j++; continue }
      if (t[j] ~ /^(-m|-A|-B|-C|-d|-D|-g|-t|-T|--max-count|--context|--after-context|--before-context|--include|--exclude|--exclude-dir|--glob|--type|--type-not|--label)$/) j++
      continue
    }
    pos[++np] = t[j]
  }
  if (!havepat) { for (j = 1; j < np; j++) pos[j] = pos[j + 1]; np-- }
  return np
}
{
  if (mode == "path") { r = fname($0); if (r != "") { print r; exit } ; next }
  line = $0
  if (line == "env") { print "environment dump (env)"; exit }
  gsub(/[<>=:,]/, " ", line)
  n = split(line, t, " ")
  c = t[1]
  if (c == "printenv") { print "environment dump (printenv)"; exit }
  if (c == "set" && n == 1) { print "environment dump (set)"; exit }
  if ((c == "export" || c == "declare" || c == "typeset") && (n == 1 || t[2] ~ /^-[a-z]*[px]/)) { print "environment dump (" c ")"; exit }
  if (c == "docker") {
    s = " " line " "
    if (s ~ / inspect /) { print "docker inspect"; exit }
    if (s ~ / exec / && s ~ / (env|printenv|set) /) { print "docker exec environment dump"; exit }
    if (s ~ / compose / && s ~ / config / && s !~ / (-q|--quiet) /) { print "docker compose config without -q"; exit }
  }
  if (c ~ /^[ef]?grep$/) {
    rec = 0
    for (j = 2; j <= n; j++) if (t[j] ~ /^--(recursive|dereference-recursive)$/ || t[j] ~ /^-[A-Za-z]*[rR][A-Za-z]*$/) rec = 1
    if (rec) {
      np = search_paths(2)
      if (np < 1 && full) { print "recursive grep without a path"; exit }
      for (j = 1; j <= np; j++) if (unsafe(pos[j])) { print "recursive grep over " pos[j]; exit }
    }
  }
  if (c == "rg") {
    noign = 0
    for (j = 2; j <= n; j++) if (t[j] ~ /^(-u+|--no-ignore.*|--hidden|-\.)$/) noign = 1
    if (noign) {
      np = search_paths(2)
      if (np < 1 && full) { print "rg without ignore rules and without a path"; exit }
      for (j = 1; j <= np; j++) if (unsafe(pos[j])) { print "rg without ignore rules over " pos[j]; exit }
    }
  }
  if (c == "find") {
    ex = 0
    for (j = 2; j <= n; j++) if (t[j] ~ /^-(exec|execdir|ok|okdir)$/) ex = 1
    if (ex) {
      np = 0; bad = 0
      for (j = 2; j <= n && t[j] !~ /^[-(!]/; j++) { np++; if (unsafe(t[j])) bad = 1 }
      if ((np == 0 && full) || bad) { print "find -exec over the repository root"; exit }
    }
  }
  if (!full) next
  meta = (c ~ /^(ls|test|\[|stat|echo|printf)$/) || (c == "find" && !ex)
  if (c == "git") { for (j = 2; j <= n && t[j] ~ /^-/; j++) ; meta = (t[j] ~ /^(check-ignore|ls-files|status|log)$/) }
  if (meta) next
  for (j = 1; j <= n; j++) { r = fname(t[j]); if (r != "") { print r; exit } }
}'

if [ "$tool" = Bash ]; then
  if printf '%s\n' "$target" | grep -Eq '\$\{?(TX_SERVER_PASSWORD|SCT_DOWNLOAD_TOKEN|UMLS_API_KEY)'; then
    reason="secret variable expansion"
  else
    data=$(printf '%s\n' "$target" | strip_heredocs)
    reason=$(
      {
        printf '%s\n' "$data" | remove_quotes | segments | normalize | awk -v mode=bash -v full=1 -v root="$root" "$checks"
        printf '%s\n' "$data" | split_quotes | segments | normalize | awk -v mode=bash -v full=0 -v root="$root" "$checks"
      } | head -n 1
    )
  fi
else
  reason=$(printf '%s\n' "$target" | awk -v mode=path -v root="$root" "$checks")
fi

if [ -n "$reason" ]; then
  echo "Blocked by repo policy ($reason): do not read .env files, secrets/, keys/certificates or secret values. Ask the user for what you need; .env.default is safe to read. Limit searches to subdirectories or use the Grep tool." >&2
  exit 2
fi
exit 0
