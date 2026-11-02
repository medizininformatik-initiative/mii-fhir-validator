# Handles heredoc bodies that `cat` or `tee` writes to a file: that text is data (docs, config),
# not commands, so its words are not checked as commands.
#   - Quoted delimiter (<<'EOF', <<"EOF", <<\EOF): the shell expands nothing; the body is dropped.
#   - Unquoted delimiter (<<EOF): the shell runs $(...) and `...` inside the body; only those
#     command substitutions are kept, one per line, so the hooks check them.
# A heredoc read by any other command, or piped onward (`cat <<EOF | sh`), keeps its whole body.

function substitutions(s,   out, i, j, n, d, c, start) {
  out = ""; n = length(s); i = 1
  while (i <= n) {
    if (substr(s, i, 2) == "$(") {
      d = 1; i += 2; start = i
      while (i <= n && d > 0) {
        c = substr(s, i, 1)
        if (c == "(") d++
        else if (c == ")") d--
        i++
      }
      out = out substr(s, start, i - start - (d == 0 ? 1 : 0)) "\n"
      continue
    }
    if (substr(s, i, 1) == "`") {
      j = index(substr(s, i + 1), "`")
      if (j == 0) { out = out substr(s, i + 1) "\n"; break }
      out = out substr(s, i + 1, j - 1) "\n"
      i += j + 1
      continue
    }
    i++
  }
  return out
}

{
  if (delim != "") {
    line = $0
    if (tabs) sub(/^\t+/, "", line)
    if (line == delim) { delim = ""; next }
    if (!quoted) printf "%s", substitutions($0)
    next
  }
  print
  if (match($0, /<<-?[ \t]*['"\\]?[A-Za-z_][A-Za-z0-9_]*['"]?/) && substr($0, RSTART - 1, 1) != "<") {
    head = substr($0, 1, RSTART - 1)
    rest = substr($0, RSTART + RLENGTH)
    tok = substr($0, RSTART, RLENGTH)
    sub(/.*[;&|(][ \t]*/, "", head)
    sub(/^[ \t]+/, "", head)
    if (head ~ /^(cat|tee)([ \t]|$)/ && rest !~ /\|/) {
      tabs = (tok ~ /^<<-/)
      sub(/^<<-?[ \t]*/, "", tok)
      quoted = (tok ~ /['"\\]/)
      gsub(/['"\\]/, "", tok)
      delim = tok
    }
  }
}
