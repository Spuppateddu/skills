#!/usr/bin/env bash
#
# Per-branch memory for branch-review, so repeated reviews converge instead of
# looping. Every finding the review reports is written here with an id and a
# status; the next review reads the ledger first and refuses to re-litigate what
# it already said.
#
#   review_ledger.sh start
#       Open a new review round: bump the round counter, print it, print the
#       whole ledger. Run this ONCE per review, before reporting.
#
#   review_ledger.sh show
#       Print the round counter and the ledger without bumping anything.
#
#   review_ledger.sh add <status> <severity> <path[:line]> <title...>
#       Record a finding. Prints the id it assigned.
#
#   review_ledger.sh bump <id> [status]
#       Same finding seen again this round: raise its seen-count, optionally
#       change its status.
#
#   review_ledger.sh close <id> <status> [note...]
#       Settle a finding: FIXED, WONTFIX, CONFLICT, STALE.
#
#   review_ledger.sh reset
#       Wipe this branch's ledger and start from round 0.
#
# Statuses:
#   OPEN      reported, not resolved yet
#   FIXED     the defect is gone from the diff
#   WONTFIX   deliberately not fixing it — never report it again
#   CONFLICT  a later finding wanted to undo an earlier fix; both are frozen
#   STALE     the code it pointed at no longer exists in the diff
#
# The ledger lives inside .git/, so it is never committed and never shows up in
# `git status`. It is per-branch: switching branches switches ledgers.
#
# bash 3.2 compatible (macOS default). No deps beyond git.
#
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "ERROR: not inside a git repository" >&2; exit 1; }

GIT_DIR="$(git rev-parse --git-dir)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
SAFE_BRANCH="$(printf '%s' "$BRANCH" | tr -c 'A-Za-z0-9._-' '_')"
DIR="$GIT_DIR/branch-review"
LEDGER="$DIR/$SAFE_BRANCH.tsv"
ROUNDFILE="$DIR/$SAFE_BRANCH.round"

# Fields are tab-separated: id, round_first, round_last, seen, status, severity,
# location, title, note.
SEP=$'\t'

ensure() {
  mkdir -p "$DIR"
  [ -f "$LEDGER" ] || : >"$LEDGER"
  [ -f "$ROUNDFILE" ] || echo 0 >"$ROUNDFILE"
}

round_now() { ensure; cat "$ROUNDFILE"; }

next_id() {
  ensure
  last="$(awk -F"$SEP" 'BEGIN{m=0} $1+0>m{m=$1+0} END{print m}' "$LEDGER")"
  echo $((last + 1))
}

# One tab-free line, so a title can never break the record layout.
clean() { printf '%s' "$*" | tr '\t\n' '  ' | sed 's/  */ /g;s/^ //;s/ $//'; }

print_ledger() {
  ensure
  if [ ! -s "$LEDGER" ]; then
    echo "(empty — nothing has been reported on this branch yet)"
    return
  fi
  awk -F"$SEP" '
    { printf "#%-3s %-8s %-8s seen:%-2s rounds:%s-%s  %s\n        %s%s\n",
        $1, $5, $6, $4, $2, $3, $7, $8, ($9 == "" ? "" : "\n        note: " $9) }
  ' "$LEDGER"
}

MODE="${1:-show}"

case "$MODE" in
  start)
    ensure
    r=$(( $(cat "$ROUNDFILE") + 1 ))
    echo "$r" >"$ROUNDFILE"
    echo "=== REVIEW ROUND ==="
    echo "branch: $BRANCH"
    echo "round:  $r"
    if [ "$r" -ge 4 ]; then
      echo "note:   round cap reached — report only NEW critical/high findings"
    fi
    echo
    echo "=== LEDGER (findings already reported on this branch) ==="
    print_ledger
    ;;

  show)
    echo "=== REVIEW ROUND ==="
    echo "branch: $BRANCH"
    echo "round:  $(round_now)"
    echo
    echo "=== LEDGER ==="
    print_ledger
    ;;

  add)
    status="${2:?usage: review_ledger.sh add <status> <severity> <path[:line]> <title...>}"
    sev="${3:?missing severity}"
    loc="${4:?missing path[:line]}"
    shift 4
    title="$(clean "$@")"
    [ -n "$title" ] || { echo "ERROR: a title is required" >&2; exit 1; }
    ensure
    r="$(cat "$ROUNDFILE")"
    [ "$r" -eq 0 ] && r=1
    id="$(next_id)"
    printf '%s\t%s\t%s\t1\t%s\t%s\t%s\t%s\t\n' \
      "$id" "$r" "$r" "$(clean "$status")" "$(clean "$sev")" "$(clean "$loc")" "$title" >>"$LEDGER"
    echo "$id"
    ;;

  bump|close)
    id="${2:?usage: review_ledger.sh $MODE <id> ...}"
    ensure
    grep -q "^$id$SEP" "$LEDGER" || { echo "ERROR: no finding #$id on this branch" >&2; exit 1; }
    if [ "$MODE" = close ]; then
      newstatus="${3:?usage: review_ledger.sh close <id> <status> [note...]}"
      shift 3
      note="$(clean "$@")"
    else
      newstatus="${3:-}"
      note=""
    fi
    r="$(cat "$ROUNDFILE")"
    [ "$r" -eq 0 ] && r=1
    tmp="$LEDGER.tmp.$$"
    awk -F"$SEP" -v OFS="$SEP" -v id="$id" -v r="$r" -v st="$newstatus" -v note="$note" -v mode="$MODE" '
      $1 == id {
        $3 = r
        if (mode == "bump") $4 = $4 + 1
        if (st != "") $5 = st
        if (note != "") $9 = note
      }
      { print }
    ' "$LEDGER" >"$tmp"
    mv "$tmp" "$LEDGER"
    grep "^$id$SEP" "$LEDGER" | awk -F"$SEP" '{print "#" $1 "  " $5 "  " $6 "  " $7 "  " $8}'
    ;;

  reset)
    ensure
    : >"$LEDGER"
    echo 0 >"$ROUNDFILE"
    echo "ledger cleared for branch '$BRANCH'"
    ;;

  path)
    ensure
    echo "$LEDGER"
    ;;

  *)
    echo "ERROR: unknown mode '$MODE' (use: start | show | add | bump | close | reset | path)" >&2
    exit 1
    ;;
esac
