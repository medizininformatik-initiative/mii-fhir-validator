# shellcheck shell=sh
# Shared shell-command parsing for the policy hooks. POSIX sh + awk only; source it after
# setting hook_lib to this directory.
#
#   strip_heredocs   drops heredoc bodies that cat/tee write to a file (data, not commands)
#   split_quotes     turns quote characters into separators (finds `sh -c "..."` commands)
#   collapse_quotes  replaces each quoted string with one token Q (keeps `git -C "/a b"` intact)
#   mask_quoted_ops  masks separators inside quotes (keeps `grep 'a|b' docs` one command)
#   remove_quotes    deletes quote characters (keeps quoted paths attached to their command)
#   segments         one line per simple command, at ; & | ( ) ` { } and newlines
#   normalize        drops keywords, VAR=value and wrappers, so field 1 is the command run

: "${hook_lib:?set hook_lib to .claude/hooks/lib before sourcing segments.sh}"

# A missing awk file would yield empty output and let every command through: block instead.
for f in strip-heredocs.awk mask-quoted-ops.awk normalize.awk; do
  [ -r "$hook_lib/$f" ] || { echo "Blocked: $hook_lib/$f is missing." >&2; exit 2; }
done

strip_heredocs() { awk -f "$hook_lib/strip-heredocs.awk"; }
split_quotes() { tr "'\"" '\n\n'; }
collapse_quotes() { sed -e "s/\"[^\"]*\"/Q/g" -e "s/'[^']*'/Q/g"; }
mask_quoted_ops() { awk -f "$hook_lib/mask-quoted-ops.awk"; }
remove_quotes() { tr -d "'\""; }
segments() { tr ';&|()`{}' '\n\n\n\n\n\n\n\n'; }
normalize() { awk -f "$hook_lib/normalize.awk"; }
