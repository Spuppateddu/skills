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
    echo "ERROR: unknown mode '$MODE' (use: state | branch [base] | diff <base> <head>)" >&2
    exit 1
    ;;
esac
