#!/usr/bin/env bash
#
# Gather the git context a code review needs, tech-agnostic. Three modes:
#
#   review_context.sh state
#       Report the current branch's working-tree and unpushed state so the
#       caller can decide what to review.
#
#   review_context.sh branch [base]
#       THE DEFAULT REVIEW TARGET. Emit everything the branch changed relative
#       to <base> (auto-detected trunk when omitted): committed work, staged
#       work, unstaged work, and untracked files — as one patch. This is what
#       the branch would land, not just what it committed.
#
#   review_context.sh diff <base> <head> [--two-dot]
#       Compare two arbitrary refs. Committed content only, by definition.
#       Three-dot range (merge-base) by default; --two-dot forces <base>..<head>.
#
#   review_context.sh history [base] [max_ranges]
#       REGRESSION CONTEXT. The net diff of a branch hides history: if commit 3
#       undoes what commit 1 fixed, the range shows nothing. And a deleted line
#       looks harmless until you see it was added by a bugfix. This mode shows
#       both — intra-branch churn, prior fix commits on the changed files, and
#       who last touched every line the branch deletes or rewrites.
#
# Also prints whether the repo looks like it has a test suite, so the review
# can flag missing tests only when tests are actually expected.
#
# bash 3.2 compatible (macOS default). No external deps beyond git.
#
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "ERROR: not inside a git repository" >&2; exit 1; }

MODE="${1:-state}"

# Untracked files above this size are listed but not dumped, to keep the patch sane.
MAX_UNTRACKED_BYTES=200000

# --- test-suite detection (heuristic, language-agnostic) -------------------
detect_tests() {
  hits=""
  add() { hits="$hits$1
"; }
  # pipefail-safe: capture, then test emptiness (no SIGPIPE / multi-arg ls traps).
  has_glob() { [ -n "$(git ls-files "$@" 2>/dev/null | head -1)" ]; }
  any_file() { for f in "$@"; do [ -f "$f" ] && return 0; done; return 1; }

  # JS/TS: a "test" script or a known runner config / test dirs
  [ -f package.json ] && grep -Eq '"test"[[:space:]]*:' package.json \
    && add 'package.json has a "test" script'
  has_glob 'jest.config.*' 'vitest.config.*' && add "JS test runner config present (jest/vitest)"
  has_glob '*.test.*' '*.spec.*' '__tests__/**' \
    && add "JS/TS test files present (*.test.* / *.spec.* / __tests__)"

  # Python
  any_file pytest.ini tox.ini && add "pytest/tox config present"
  [ -f pyproject.toml ] && grep -q '\[tool.pytest' pyproject.toml && add "pyproject pytest config present"
  has_glob 'test_*.py' '*_test.py' 'tests/**/*.py' && add "Python test files present"

  # PHP
  any_file phpunit.xml phpunit.xml.dist && add "PHPUnit config present"
  has_glob '**/*Test.php' && add "PHP test files present (*Test.php)"

  # Go / Rust / Ruby / Java-Kotlin
  has_glob '*_test.go' && add "Go test files present (*_test.go)"
  [ -f Cargo.toml ] && add "Rust crate (built-in #[test] support)"
  has_glob 'spec/**/*_spec.rb' && add "RSpec files present"
  has_glob 'src/test/**' && add "JVM test sources present (src/test)"

  if [ -n "$hits" ]; then
    echo "TEST_SUITE: yes"
    printf "%s" "$hits" | sed '/^$/d;s/^/  - /'
  else
    echo "TEST_SUITE: none detected — do NOT flag missing tests"
  fi
}

# --- base detection --------------------------------------------------------
# The trunk this branch forked from. Prefer origin's declared default branch,
# then the usual names. If HEAD *is* the trunk, fall back to its upstream so
# the review still covers unpushed commits.
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

  # On the trunk itself, "the branch's work" means whatever isn't pushed yet.
  if [ -z "$cand" ] || [ "$cand" = "$cur" ] || [ "$cand" = "origin/$cur" ]; then
    up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
    [ -n "$up" ] && cand="$up"
  fi

  [ -n "$cand" ] || return 1
  echo "$cand"
}

list_untracked() { git ls-files --others --exclude-standard; }

# --- regression context ----------------------------------------------------
# Commit subjects that suggest the commit fixed something on purpose. Lines
# from such commits are the ones a hallucinating rewrite must not silently drop.
FIXISH='fix|bug|revert|regress|hotfix|patch|secur|vuln|CVE|crash|leak|guard|race|deadlock|overflow|workaround|edge case|off.by.one'

# Mark fix-ish commits with '*' so they stand out in a long log.
mark_fixish() { sed -E "s/^([0-9a-f]{7,} )(.*(${FIXISH}).*)$/* \1\2/I; s/^([0-9a-f]{7,} )/  \1/"; }

# Files this branch touches more than once: the place where a later commit can
# quietly undo an earlier one.
emit_branch_churn() {
  mb="$1"
  commits="$(git rev-list "$mb"..HEAD)"
  [ -n "$commits" ] || { echo "(no commits on this branch — nothing can have been undone in-branch)"; return; }

  # Empty pretty-format => one blank line per commit, then its file names.
  churn="$(git log --pretty=format: --name-only --no-merges "$mb"..HEAD \
    | grep -v '^$' | sort | uniq -c | sort -rn | awk '$1 > 1 { $1=$1; print }')"
  [ -n "$churn" ] || { echo "(no file touched by more than one commit)"; return; }

  printf "%s\n" "$churn" | while read -r n f; do
    echo "$f — touched by $n commits:"
    git log --format='%h %ad %s' --date=short --no-merges "$mb"..HEAD -- "$f" | mark_fixish
    echo
  done
}

# What the changed files were fixed for BEFORE this branch existed.
emit_prior_fixes() {
  mb="$1"; depth="${2:-12}"
  files="$(git diff --name-only "$mb" | head -60)"
  [ -n "$files" ] || { echo "(no tracked file changed)"; return; }

  printf "%s\n" "$files" | while IFS= read -r f; do
    log="$(git log --format='%h %ad %s' --date=short --no-merges -n "$depth" "$mb" -- "$f" 2>/dev/null || true)"
    [ -n "$log" ] || continue
    echo "$f"
    printf "%s\n" "$log" | mark_fixish | sed 's/^/  /'
    echo
  done
}

# For every line the branch deletes or rewrites, the commits that last touched
# it. This is the direct answer to "why was this line here?".
emit_line_provenance() {
  mb="$1"; max_ranges="${2:-40}"

  ranges="$(git diff -U0 --no-color "$mb" | awk -v max="$max_ranges" '
    /^--- \/dev\/null/ { old=""; next }
    /^--- a\//         { old=substr($0,7); next }
    /^--- /            { old=""; next }
    /^@@ / {
      if (old == "") next
      h = $2; sub(/^-/, "", h)
      n = split(h, p, ",")
      a = p[1] + 0; b = (n > 1 ? p[2] + 0 : 1)
      if (b == 0) next          # pure insertion: nothing pre-existing was touched
      if (shown >= max) { skipped++; next }
      shown++
      print old "\t" a "\t" (a + b - 1)
    }
    END { if (skipped) print "\t\tSKIPPED " skipped }
  ')"

  [ -n "$ranges" ] || { echo "(this branch deletes or rewrites no pre-existing line)"; return; }

  printf "%s\n" "$ranges" | while IFS="$(printf '\t')" read -r f a b; do
    if [ -z "$f" ]; then
      echo "(+ $b more changed ranges not analysed — rerun with a higher max_ranges)"
      continue
    fi
    echo "$f:$a-$b"
    git log -L "$a,$b:$f" -s -n 3 --format='%h %ad %s' --date=short "$mb" 2>/dev/null \
      | mark_fixish | sed 's/^/  /' || echo "  (no history)"
    echo
  done
}

# Dump untracked files as add-patches, so they read like the rest of the diff.
emit_untracked_patches() {
  files="$(list_untracked)"
  [ -n "$files" ] || { echo "(none)"; return; }

  printf "%s\n" "$files" | while IFS= read -r f; do
    [ -f "$f" ] || continue
    size="$(wc -c <"$f" | tr -d ' ')"
    if [ "$size" -gt "$MAX_UNTRACKED_BYTES" ]; then
      echo "--- SKIPPED (larger than ${MAX_UNTRACKED_BYTES} bytes): $f"
      continue
    fi
    # --no-index exits 1 on difference; that is the expected path here.
    git diff --no-index --binary -- /dev/null "$f" || true
  done
}

case "$MODE" in
  state)
    branch="$(git rev-parse --abbrev-ref HEAD)"
    echo "=== CURRENT BRANCH ==="
    echo "$branch"
    echo

    echo "=== DETECTED BASE ==="
    detect_base || echo "(none — pass a base explicitly)"
    echo

    echo "=== UNCOMMITTED CHANGES (working tree + index) ==="
    if [ -n "$(git status --porcelain)" ]; then
      git status --short
    else
      echo "(clean)"
    fi
    echo

    echo "=== UNTRACKED FILES ==="
    untracked="$(list_untracked)"
    [ -n "$untracked" ] && echo "$untracked" || echo "(none)"
    echo

    echo "=== UNPUSHED COMMITS ==="
    if upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
      ahead="$(git rev-list --count "$upstream"..HEAD)"
      echo "upstream: $upstream  (ahead by $ahead)"
      [ "$ahead" -gt 0 ] && git log --oneline "$upstream"..HEAD
    else
      echo "no upstream configured for '$branch' — every commit here may be unpushed"
      git log --oneline -10
    fi
    echo

    detect_tests
    ;;

  branch)
    base="${2:-}"
    if [ -z "$base" ]; then
      base="$(detect_base || true)"
      [ -n "$base" ] || { echo "ERROR: could not detect a base branch — pass one: review_context.sh branch <base>" >&2; exit 1; }
    fi
    git rev-parse --verify --quiet "$base" >/dev/null \
      || { echo "ERROR: unknown ref '$base'" >&2; exit 1; }

    mb="$(git merge-base "$base" HEAD)"

    echo "=== REVIEW TARGET ==="
    echo "branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "base:   $base (merge-base ${mb})"
    echo "scope:  committed + staged + unstaged + untracked"
    echo

    echo "=== COMMITS ON THIS BRANCH ==="
    if [ -n "$(git rev-list "$mb"..HEAD)" ]; then
      git log --oneline "$mb"..HEAD
    else
      echo "(none — all work is uncommitted)"
    fi
    echo

    echo "=== WORKING TREE STATUS ==="
    if [ -n "$(git status --porcelain)" ]; then
      git status --short
    else
      echo "(clean)"
    fi
    echo

    detect_tests
    echo

    # `git diff <commit>` compares that commit against the working tree, so this
    # single patch spans committed, staged and unstaged changes at once.
    echo "=== CHANGED FILES (stat: tracked, committed + uncommitted) ==="
    git diff --stat "$mb"
    echo

    echo "=== PATCH (tracked: committed + staged + unstaged) ==="
    git diff "$mb"
    echo

    echo "=== PATCH (untracked files, shown as additions) ==="
    emit_untracked_patches
    echo
    echo "=== NEXT ==="
    echo "This patch is the branch's NET result: it cannot show a later commit undoing an"
    echo "earlier one, and it does not say why a deleted line existed. Run:"
    echo "  review_context.sh history $base"
    ;;

  history)
    base="${2:-}"
    max_ranges="${3:-40}"
    if [ -z "$base" ]; then
      base="$(detect_base || true)"
      [ -n "$base" ] || { echo "ERROR: could not detect a base branch — pass one: review_context.sh history <base>" >&2; exit 1; }
    fi
    git rev-parse --verify --quiet "$base" >/dev/null \
      || { echo "ERROR: unknown ref '$base'" >&2; exit 1; }

    mb="$(git merge-base "$base" HEAD)"

    echo "=== REGRESSION CONTEXT ==="
    echo "branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "base:   $base (merge-base ${mb})"
    echo "'*' marks a commit whose subject reads like a deliberate fix."
    echo

    echo "=== INTRA-BRANCH CHURN (files this branch touched more than once) ==="
    echo "A later commit here may have reverted or broken what an earlier one fixed —"
    echo "the net patch would show no trace of it."
    echo
    emit_branch_churn "$mb"
    echo

    echo "=== PRIOR HISTORY OF THE CHANGED FILES (before the merge-base) ==="
    echo "What these files were already fixed for. A change that reopens one of these is a regression."
    echo
    emit_prior_fixes "$mb"
    echo

    echo "=== PROVENANCE OF DELETED / REWRITTEN LINES ==="
    echo "For each pre-existing line range this branch removes or rewrites, the commits that"
    echo "last touched it. Read these before accepting the change: they say why the line existed."
    echo
    emit_line_provenance "$mb" "$max_ranges"
    ;;

  diff)
    base="${2:?usage: review_context.sh diff <base> <head> [--two-dot]}"
    head="${3:?usage: review_context.sh diff <base> <head> [--two-dot]}"
    sep="..."
    [ "${4:-}" = "--two-dot" ] && sep=".."

    for ref in "$base" "$head"; do
      git rev-parse --verify --quiet "$ref" >/dev/null \
        || { echo "ERROR: unknown ref '$ref'" >&2; exit 1; }
    done

    range="$base$sep$head"
    echo "=== REVIEW RANGE ==="
    echo "$range"
    echo "scope:  committed content only"
    echo

    # Comparing against the checked-out branch silently drops its dirty state.
    cur="$(git rev-parse --abbrev-ref HEAD)"
    if [ "$head" = "$cur" ] || [ "$head" = "HEAD" ]; then
      if [ -n "$(git status --porcelain)" ]; then
        echo "=== WARNING ==="
        echo "'$head' is checked out and has uncommitted/untracked changes, which this"
        echo "range does NOT include. Use 'review_context.sh branch $base' to review them too."
        git status --short
        echo
      fi
    fi

    echo "=== CHANGED FILES (stat) ==="
    git diff --stat "$range"
    echo

    detect_tests
    echo

    echo "=== PATCH ==="
    git diff "$range"
    ;;

  *)
    echo "ERROR: unknown mode '$MODE' (use: state | branch [base] | diff <base> <head> | history [base])" >&2
    exit 1
    ;;
esac
