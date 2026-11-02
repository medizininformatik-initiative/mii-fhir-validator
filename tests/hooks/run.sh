#!/bin/sh
# Regression tests for the Claude Code policy hooks in .claude/hooks.
# Feeds synthetic hook input (JSON) to each hook and compares the exit status with
# tests/hooks/cases.tsv and the malformed-input cases below. Commands are never executed.

set -u

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
hooks="$repo_dir/.claude/hooks"
tab=$(printf '\t')
passed=0
failed=0

# Absolute paths in the cases use this project root.
CLAUDE_PROJECT_DIR=/Users/someone/git/mii-fhir-validator
export CLAUDE_PROJECT_DIR

check() { # name expected actual
  if [ "$2" = "$3" ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: $1 (expected exit $2, got $3)"
  fi
}

hook_path() {
  case "$1" in
    git) echo "$hooks/block-git-writes.sh" ;;
    secret) echo "$hooks/block-secret-reads.sh" ;;
  esac
}

# cases.tsv: hook, expected exit, tool, input. A literal \n in the input becomes a newline,
# a literal \t a tab.
while IFS="$tab" read -r hook want tool value; do
  case "$hook" in '' | '#'*) continue ;; esac
  case "$tool" in
    Bash) name="Bash" field="command" ;;
    Grep) name="Grep" field="path" ;;
    GrepGlob) name="Grep" field="glob" ;;
    *) name="$tool" field="file_path" ;;
  esac
  printf '%s' "$value" | awk 'BEGIN { RS = "\001" } { gsub(/\\n/, "\n"); gsub(/\\t/, "\t"); printf "%s", $0 }' |
    jq -Rs --arg tool "$name" --arg field "$field" '{tool_name: $tool, tool_input: {($field): .}}' |
    "$(hook_path "$hook")" 2>/dev/null
  check "$hook $tool: $value" "$want" "$?"
done < "$repo_dir/tests/hooks/cases.tsv"

# Malformed input must block (fail closed). Columns: hook, expected exit, raw input.
while IFS="$tab" read -r hook want raw; do
  printf '%s' "$raw" | "$(hook_path "$hook")" 2>/dev/null
  check "$hook malformed: $raw" "$want" "$?"
done <<EOF
git	2	not json
git	2	{}
git	2	{"tool_name":"Bash"}
git	2	{"tool_name":"Bash","tool_input":{"command":42}}
git	2	{"tool_name":"Bash","tool_input":"git push"}
secret	2	not json
secret	2	{}
secret	2	{"tool_input":{"command":"ls"}}
secret	2	{"tool_name":"Bash"}
secret	2	{"tool_name":"Bash","tool_input":{"command":42}}
secret	2	{"tool_name":"Read","tool_input":{}}
secret	2	{"tool_name":"Read","tool_input":{"file_path":7}}
secret	2	{"tool_name":"Edit","tool_input":{"command":"ls"}}
secret	2	{"tool_name":"Grep","tool_input":{"path":1}}
secret	2	{"tool_name":"Grep","tool_input":"x"}
secret	2	{"tool_name":"Unknown","tool_input":{"command":"ls"}}
secret	0	{"tool_name":"Grep","tool_input":{"pattern":"proxy"}}
EOF

# With a real secrets/ directory in the project root, the bare word counts as that path.
root_with_dir=$(mktemp -d)
mkdir "$root_with_dir/secrets"
while IFS="$tab" read -r want cmd; do
  jq -n --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}' |
    CLAUDE_PROJECT_DIR="$root_with_dir" "$hooks/block-secret-reads.sh" 2>/dev/null
  check "secret with secrets/ present: $cmd" "$want" "$?"
done <<EOF
2	tar czf backup.tgz secrets
2	cp -r secrets /tmp
0	ls secrets
EOF
rm -rf "$root_with_dir"

# One missing awk file of the library must block, not let every command through.
for f in mask-quoted-ops.awk normalize.awk strip-heredocs.awk; do
  partial=$(mktemp -d)
  mkdir "$partial/lib"
  cp "$hooks/block-secret-reads.sh" "$partial/"
  cp "$hooks"/lib/* "$partial/lib/"
  rm "$partial/lib/$f"
  printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | "$partial/block-secret-reads.sh" 2>/dev/null
  check "secret: lib/$f missing" 2 "$?"
  rm -rf "$partial"
done

# A missing jq or a missing hook library must block, not allow.
for hook in git secret; do
  nojq=$(mktemp -d)
  for tool in sh tr sed awk grep cat head dirname; do ln -s "$(command -v "$tool")" "$nojq/$tool"; done
  printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | PATH="$nojq" "$(hook_path "$hook")" 2>/dev/null
  check "$hook: jq missing" 2 "$?"
  rm -rf "$nojq"

  copy=$(mktemp -d)
  cp "$(hook_path "$hook")" "$copy/"
  printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | "$copy/$(basename "$(hook_path "$hook")")" 2>/dev/null
  check "$hook: lib missing" 2 "$?"
  rm -rf "$copy"
done

echo "hooks: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
