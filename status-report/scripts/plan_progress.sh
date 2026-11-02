#!/usr/bin/env bash
# plan_progress.sh <plan.md> — progress and pace of a plan-write / plan-execute plan.
#
# Prints:
#   COUNTS     tasks per state ([ ] [~] [x] [!]) and the percentage done
#   PHASES     the same per "## Phase" heading
#   CURRENT    the [~] task(s), else the next [ ] task
#   BLOCKED    every [!] task
#   TIMING     when each task was ticked [x], read from Claude Code session
#              logs (~/.claude/projects/*/*.jsonl), and an ETA from that pace
#
# Needs bash, awk, jq. Read-only: it never writes anything.
set -eu

PLAN="${1:-}"
[ -n "$PLAN" ] || { echo "ERROR: usage: plan_progress.sh <plan.md>" >&2; exit 1; }
[ -f "$PLAN" ] || { echo "ERROR: plan file not found: $PLAN" >&2; exit 1; }
PLAN_ABS="$(cd "$(dirname "$PLAN")" && pwd)/$(basename "$PLAN")"
BASE="$(basename "$PLAN")"

# --- counts, phases, current task -------------------------------------------
awk '
  function state(l) {
    if (l ~ /\[[xX]\]/) return "done"; if (l ~ /\[~\]/) return "doing"
    if (l ~ /\[!\]/) return "blocked"; return "todo"
  }
  function label(l) { sub(/^[ \t]*[-*][ \t]+\[.\][ \t]+/, "", l); return substr(l, 1, 110) }
  /^##[ \t]/ { ph = $0; sub(/^#+[ \t]+/, "", ph); if (!(ph in seen)) { seen[ph] = 1; order[++np] = ph } next }
  /^[ \t]*[-*][ \t]+\[.\][ \t]/ {
    s = state($0); n[s]++; tot++; pt[ph]++; if (s == "done") pd[ph]++
    if (s == "doing") doing[++nd] = label($0)
    if (s == "blocked") blk[++nb] = label($0)
    if (s == "todo" && next_t == "") next_t = label($0)
  }
  END {
    if (!tot) { print "COUNTS: no checklist in this file"; exit }
    printf "COUNTS: total=%d done=%d doing=%d todo=%d blocked=%d left=%d percent_done=%d%%\n",
      tot, n["done"], n["doing"], n["todo"], n["blocked"], tot - n["done"], int(100 * n["done"] / tot)
    print "PHASES:"
    for (i = 1; i <= np; i++) if (pt[order[i]])
      printf "  %-60s %d/%d (%d%%)\n", substr(order[i], 1, 60), pd[order[i]], pt[order[i]], int(100 * pd[order[i]] / pt[order[i]])
    print "CURRENT:"
    if (nd) for (i = 1; i <= nd; i++) print "  [~] " doing[i]
    else if (next_t != "") print "  (none in progress) NEXT: [ ] " next_t
    else print "  (nothing left)"
    if (nb) { print "BLOCKED:"; for (i = 1; i <= nb; i++) print "  [!] " blk[i] }
  }' "$PLAN"

# --- timing from session logs ------------------------------------------------
# A plan moves between plan/to-start, in-progress and done, so match any path
# under the same plan/ root that ends with the same file name.
PLAN_ROOT="$(dirname "$(dirname "$PLAN_ABS")")"
LEFT="$(awk '/^[ \t]*[-*][ \t]+\[.\][ \t]/ { if ($0 !~ /\[[xX]\]/) l++ } END { print l + 0 }' "$PLAN")"
LOGS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

echo "TIMING:"
if ! command -v jq >/dev/null 2>&1; then echo "  not measurable: jq is not installed"; exit 0; fi
FILES="$(grep -rlF --include='*.jsonl' "$BASE" "$LOGS" 2>/dev/null || true)"
if [ -z "$FILES" ]; then echo "  not measurable: no session log edits this plan"; exit 0; fi

# One line per edit of the plan: "<iso timestamp> <tasks newly ticked [x]>"
EVENTS="$(printf '%s\n' "$FILES" | while IFS= read -r f; do
  jq -r --arg root "$PLAN_ROOT/" --arg base "/$BASE" '
    select(.type == "assistant") | .timestamp as $ts
    | .message.content[]? | select(.type == "tool_use")
    | select((.name == "Edit" or .name == "Write" or .name == "MultiEdit"))
    | select((.input.file_path // "") | startswith($root) and endswith($base))
    | def ticks(s): [ (s // "") | scan("\\[[xX]\\]") ] | length;
      (if .name == "Edit" then ticks(.input.new_string) - ticks(.input.old_string)
       elif .name == "MultiEdit" then ([.input.edits[]? | ticks(.new_string) - ticks(.old_string)] | add // 0)
       else 0 end) as $d
    | "\($ts) \($d)"' "$f" 2>/dev/null || true
done | sort)"

if [ -z "$EVENTS" ]; then echo "  not measurable: no logged edits of this plan"; exit 0; fi

printf '%s\n' "$EVENTS" | LEFT="$LEFT" awk '
  function secs(t,   d, c) {   # ISO 8601 UTC -> epoch seconds (no external date call)
    split(substr(t, 1, 10), d, "-"); split(substr(t, 12, 8), c, ":")
    y = d[1]; m = d[2]; dd = d[3]; if (m <= 2) { y--; m += 12 }
    days = 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + dd
    return days * 86400 + c[1] * 3600 + c[2] * 60 + c[3]
  }
  function dur(s) { s = int(s); if (s < 3600) return int(s / 60 + 0.5) "m"; return int(s / 3600) "h" sprintf("%02d", int((s % 3600) / 60)) "m" }
  {
    t = secs($1); if (NR == 1) { first = t; first_iso = $1 }
    if (prev && t - prev < 1800) active += t - prev      # gaps over 30 min are breaks
    prev = t; last_iso = $1
    for (k = 0; k < $2; k++) done_t[++nd] = t
  }
  END {
    printf "  first edit of the plan: %s\n  last edit of the plan:  %s\n", first_iso, last_iso
    printf "  wall-clock span: %s   active time (breaks over 30m removed): %s\n", dur(prev - first), dur(active)
    printf "  tasks ticked [x] in logged sessions: %d   left: %d\n", nd, ENVIRON["LEFT"]
    if (nd < 3) { print "  ETA: not measurable (fewer than 3 tasks ticked in the logs)"; exit }
    # pace = median gap between consecutive ticks, breaks (>2h) left out
    g = 0; for (i = 2; i <= nd; i++) { x = done_t[i] - done_t[i-1]; if (x < 7200) gap[++g] = x }
    if (g < 2) { print "  ETA: not measurable (too few ticks close together)"; exit }
    for (i = 1; i <= g; i++) for (j = i + 1; j <= g; j++) if (gap[j] < gap[i]) { x = gap[i]; gap[i] = gap[j]; gap[j] = x }
    med = (g % 2) ? gap[(g + 1) / 2] : (gap[g / 2] + gap[g / 2 + 1]) / 2
    if (med < 60) med = 60
    printf "  pace: median %s per task (from %d gaps)\n", dur(med), g
    printf "  ETA: about %s of active work for %d tasks left (range %s - %s)\n",
      dur(med * ENVIRON["LEFT"]), ENVIRON["LEFT"], dur(gap[int((g + 3) / 4)] * ENVIRON["LEFT"]), dur(gap[int((3 * g + 3) / 4)] * ENVIRON["LEFT"])
  }'
