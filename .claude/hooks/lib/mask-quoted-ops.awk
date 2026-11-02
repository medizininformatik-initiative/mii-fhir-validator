# Replaces the segment separators ; & | ( ) ` { } and newlines inside quoted strings with "_",
# so `segments` does not split a quoted grep pattern like 'a\|b' into two commands.
# Single-quoted text is always literal. Double-quoted text is masked only when it contains no
# $( and no backtick, because command substitutions there run and must stay visible.
# Reads the whole input as one record; quote characters themselves are kept.
function mask(b) { gsub(/[;&|(){}`\n]/, "_", b); return b }
BEGIN { RS = "\001" }
{
  s = $0; n = length(s); out = ""; i = 1
  while (i <= n) {
    ch = substr(s, i, 1)
    if (ch == "\\") { out = out substr(s, i, 2); i += 2; continue }
    if (ch == "'") {
      j = index(substr(s, i + 1), "'")
      if (!j) { out = out substr(s, i); break }
      out = out "'" mask(substr(s, i + 1, j - 1)) "'"
      i += j + 1
      continue
    }
    if (ch == "\"") {
      for (k = i + 1; k <= n; k++) {
        c = substr(s, k, 1)
        if (c == "\\") { k++; continue }
        if (c == "\"") break
      }
      if (k > n) { out = out substr(s, i); break }
      body = substr(s, i + 1, k - i - 1)
      if (body !~ /\$\(|`/) body = mask(body)
      out = out "\"" body "\""
      i = k + 1
      continue
    }
    out = out ch; i++
  }
  printf "%s", out
}
