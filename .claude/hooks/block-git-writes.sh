#!/bin/sh
# PreToolUse hook (Bash): blocks git/gh commands that stage, write history or touch the remote.
# The user makes all commits and pushes. Exit 2 blocks the call and shows stderr to the agent.
# Fails closed: missing jq or input without a string tool_input.command blocks the call.
#
# The command is checked twice (see lib/segments.sh): split at quotes, which finds
# `sh -c "git commit"`, and with quoted strings collapsed, which keeps `git -C "/a b" commit`
# intact. Heredoc bodies written by cat/tee are data and are not checked.

hook_lib="$(dirname "$0")/lib"
[ -r "$hook_lib/segments.sh" ] || { echo "Blocked: $hook_lib/segments.sh is missing." >&2; exit 2; }
. "$hook_lib/segments.sh"

command -v jq >/dev/null 2>&1 || {
  echo "Blocked: jq is required by .claude/hooks/block-git-writes.sh but is not installed." >&2
  exit 2
}

cmd=$(jq -er '.tool_input.command | strings') || {
  echo "Blocked: block-git-writes.sh needs a string tool_input.command in the hook input." >&2
  exit 2
}

data=$(printf '%s\n' "$cmd" | strip_heredocs)

hit=$(
  {
    printf '%s\n' "$data" | split_quotes
    printf '%s\n' "$data" | collapse_quotes
  } | segments | normalize | awk '
    {
      n = split($0, t, " ")
      if (t[1] == "git") {
        i = 2
        while (i <= n && t[i] ~ /^-/) {
          if (t[i] ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--exec-path|--config-env)$/) i++
          i++
        }
        if (i <= n && t[i] ~ /^(add|stage|rm|mv|stash|commit|commit-tree|update-ref|push|merge|rebase|reset|tag|cherry-pick|revert|am|pull)$/) {
          print "git " t[i]; exit
        }
      } else if (t[1] == "gh") {
        if (t[2] == "pr" && t[3] ~ /^(create|merge)$/) { print "gh pr " t[3]; exit }
        if (t[2] == "release" && t[3] ~ /^(create|edit|delete)$/) { print "gh release " t[3]; exit }
      }
    }'
)

if [ -n "$hit" ]; then
  echo "Blocked by repo policy (\`$hit\`): the user stages, commits, pushes, tags and opens PRs. Stop, summarize the diff and propose a commit message instead." >&2
  exit 2
fi
exit 0
