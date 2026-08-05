#!/usr/bin/env bash
#
# Gather the ground truth behind ONE code-review finding, so it can be judged
# real or hallucinated. Tech-agnostic; needs only git + awk.
#
#   finding_context.sh <file>[:<line>] [line] [radius] [base]
#
#     finding_context.sh app/Services/OrderReport.php:42
#     finding_context.sh app/Services/OrderReport.php 42 40
#     finding_context.sh src/api.ts:88 60 origin/main
#
# <file> may be the path exactly as the review printed it, a repo-relative
# path, or just a basename — it is resolved against the index either way.
# radius defaults to 25 lines either side.
#
# Prints, in order:
#   - the resolved path (or candidates, if ambiguous)
#   - the numbered code window with the target line marked ">>"
#   - whether that line is actually part of the branch diff vs <base>
#   - git blame for the line (or "uncommitted")
#   - the nearest enclosing declaration above the line
#   - recent history for the file
#
# bash 3.2 compatible (macOS default).
#
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "ERROR: not inside a git repository" >&2; exit 1; }

RAW="${1:?usage: finding_context.sh <file>[:<line>] [line] [radius] [base]}"
shift || true

FILE="$RAW"
LINE=""
# Accept "path:42" as one argument, the form review reports use.
case "$RAW" in
  *:[0-9]*)
    FILE="${RAW%:*}"
    LINE="${RAW##*:}"
    ;;
esac

# Remaining args: [line] [radius] [base] — line only if not already parsed.
if [ -z "$LINE" ]; then
  LINE="${1:-}"
  shift || true
fi
RADIUS="${1:-25}"
[ $# -gt 0 ] && shift || true
BASE="${1:-}"

case "$LINE" in
  ''|*[!0-9]*) echo "ERROR: no valid line number given (got '${LINE:-<empty>}')" >&2; exit 1 ;;
esac

# --- resolve the path ------------------------------------------------------
resolve_file() {
  [ -f "$FILE" ] && { echo "$FILE"; return 0; }

  base_name="$(basename "$FILE")"
  # Try suffix match first (review paths are often repo-relative already),
  # then fall back to basename anywhere in the repo.
  matches="$(git ls-files -- "*$FILE" 2>/dev/null || true)"
  [ -n "$matches" ] || matches="$(git ls-files -- "*$base_name" 2>/dev/null || true)"
  # Untracked files won't be in the index; look on disk too.
  [ -n "$matches" ] || matches="$(find . -type f -name "$base_name" -not -path './.git/*' 2>/dev/null | sed 's|^\./||' || true)"

  count="$(printf "%s\n" "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$count" = "1" ]; then
    printf "%s\n" "$matches" | sed '/^$/d'
    return 0
  fi
  return 1
}

echo "=== RESOLVED FILE ==="
if resolved="$(resolve_file)"; then
  FILE="$resolved"
  echo "path:  $FILE"
  echo "line:  $LINE"
  total="$(wc -l <"$FILE" | tr -d ' ')"
  echo "lines: $total"
  if [ "$LINE" -gt "$total" ]; then
    echo "WARNING: line $LINE is past the end of the file ($total lines) —"
    echo "         the finding's location is wrong; treat its claim with suspicion."
  fi
  if git ls-files --error-unmatch "$FILE" >/dev/null 2>&1; then
    echo "tracked: yes"
  else
    echo "tracked: no (untracked / new file)"
  fi
else
  echo "NOT FOUND: '$FILE'"
  echo "Candidates with that basename:"
  git ls-files -- "*$(basename "$FILE")" 2>/dev/null | sed 's/^/  /' || true
  echo
  echo "A finding pointing at a file that does not exist is a hallucination"
  echo "unless the path is simply written differently — check the candidates."
  exit 0
fi
echo

# --- code window -----------------------------------------------------------
start=$(( LINE - RADIUS )); [ "$start" -lt 1 ] && start=1
end=$(( LINE + RADIUS ))

echo "=== CODE ($FILE, lines $start-$end; >> marks the reported line) ==="
awk -v s="$start" -v e="$end" -v t="$LINE" \
  'NR>=s && NR<=e { printf "%s %5d | %s\n", (NR==t ? ">>" : "  "), NR, $0 }' "$FILE"
echo

# --- is the line actually part of the branch diff? -------------------------
detect_base() {
  cur="$(git rev-parse --abbrev-ref HEAD)"
  cand=""
  if ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
    cand="${ref#refs/remotes/}"
  fi
  if [ -z "$cand" ]; then
    for c in origin/main origin/master main master develop; do
      git rev-parse --verify --quiet "$c" >/dev/null && { cand="$c"; break; }
    done
  fi
  if [ -z "$cand" ] || [ "$cand" = "$cur" ] || [ "$cand" = "origin/$cur" ]; then
    up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
    [ -n "$up" ] && cand="$up"
  fi
  [ -n "$cand" ] || return 1
  echo "$cand"
}

echo "=== IS THE REPORTED LINE PART OF THE CHANGE? ==="
[ -n "$BASE" ] || BASE="$(detect_base || true)"
if [ -z "$BASE" ]; then
  echo "(no base branch detected — cannot tell changed lines from pre-existing ones)"
else
  echo "base: $BASE"
  mb="$(git merge-base "$BASE" HEAD 2>/dev/null || echo "$BASE")"
  # `git diff <merge-base> -- file` spans committed + staged + unstaged, which is
  # the same scope branch-review reports against.
  patch="$(git diff -U0 "$mb" -- "$FILE" 2>/dev/null || true)"
  if [ -z "$patch" ] && ! git ls-files --error-unmatch "$FILE" >/dev/null 2>&1; then
    echo "verdict: WHOLE FILE IS NEW (untracked) — every line is part of the change"
  elif [ -z "$patch" ]; then
    echo "verdict: PRE-EXISTING — this file is unchanged vs $BASE."
    echo "         The finding is out of scope for a diff review, even if the"
    echo "         code is genuinely bad."
  else
    printf "%s\n" "$patch" | awk -v t="$LINE" '
      /^@@/ {
        # @@ -a,b +c,d @@
        plus = $3; sub(/^\+/, "", plus)
        split(plus, p, ",")
        c = p[1] + 0
        d = (length(p) > 1 ? p[2] + 0 : 1)
        if (d > 0 && t >= c && t <= c + d - 1) { hit = 1 }
        if (d > 0 && t >= c - 3 && t <= c + d + 2) { near = 1 }
      }
      END {
        if (hit)       print "verdict: CHANGED — the reported line is added/modified by this branch"
        else if (near) print "verdict: ADJACENT — the line is not itself changed, but sits inside a changed region"
        else           print "verdict: UNCHANGED LINE — the file changed, but not at this line (context only)"
      }'
    echo
    echo "--- hunks touching this file ---"
    printf "%s\n" "$patch" | grep '^@@' | sed 's/^/  /' || true
  fi
fi
echo

echo "=== BLAME FOR LINE $LINE ==="
if git ls-files --error-unmatch "$FILE" >/dev/null 2>&1; then
  git blame -L "$LINE,$LINE" --date=short -- "$FILE" 2>/dev/null \
    || echo "(blame unavailable — line may exist only in the working tree)"
else
  echo "(file is untracked — nothing to blame)"
fi
echo

# --- nearest enclosing declaration ----------------------------------------
echo "=== NEAREST DECLARATION ABOVE THE LINE ==="
awk -v t="$LINE" '
  NR <= t && /^[[:space:]]*(export[[:space:]]+)?(public|private|protected|static|async|final|abstract|pub|impl|export|declare)?[[:space:]]*(function|func|def|fn|class|interface|struct|trait|enum|type|const[[:space:]]+[A-Za-z_].*=[[:space:]]*(\(|async|function)|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\()/ {
    last = NR " | " $0
  }
  END { print (last ? last : "(none found — top-level or unrecognised syntax)") }
' "$FILE"
echo

echo "=== RECENT HISTORY FOR THIS FILE ==="
git log --oneline -8 -- "$FILE" 2>/dev/null || echo "(no history)"
