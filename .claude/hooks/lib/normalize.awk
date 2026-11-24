# Normalizes one shell segment per input line: drops shell keywords, VAR=value assignments and
# command wrappers with their options, so field 1 is the basename of the command that runs.
# `env` without a command prints the environment and is kept as the single word "env".
function base(p) { sub(/^\\/, "", p); sub(/.*\//, "", p); return p }
{
  n = split($0, t, " ")
  i = 1
  while (i <= n) {
    w = base(t[i])
    if (t[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || w ~ /^(!|\$|if|then|else|elif|do|while|until)$/) { i++; continue }
    if (w ~ /^(command|builtin|exec|eval|env|sudo|doas|nohup|time|xargs|nice|ionice|stdbuf|timeout|caffeinate)$/) {
      i++
      while (i <= n && (t[i] ~ /^-/ || (w == "env" && t[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/))) {
        if (t[i] ~ /^-(u|C|S|g|n|s|k|c|I|L|P)$/) i++
        i++
      }
      if (w == "timeout" && i <= n) i++
      if (i > n && w == "env") { print "env"; next }
      continue
    }
    break
  }
  if (i > n) next
  out = base(t[i])
  for (j = i + 1; j <= n; j++) out = out " " t[j]
  print out
}
