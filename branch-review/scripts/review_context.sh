#!/usr/bin/env bash
#
# Gather the git context a code review needs, tech-agnostic. Two modes:
#
#   review_context.sh state
#       Report the current branch's working-tree and unpushed state so the
#       caller can decide what to review (uncommitted work vs a branch diff).
#
#   review_context.sh diff <base> <head>
#       Emit the review target: changed-file stat + full patch of <head>
#       relative to <base>. Uses a three-dot range (merge-base) so only the
#       changes <head> introduces are shown, not unrelated drift on <base>.
#       Pass --two-dot as a 4th arg to force a plain <base>..<head> range.
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

case "$MODE" in
  state)
    branch="$(git rev-parse --abbrev-ref HEAD)"
    echo "=== CURRENT BRANCH ==="
    echo "$branch"
    echo

    echo "=== UNCOMMITTED CHANGES (working tree + index) ==="
    if [ -n "$(git status --porcelain)" ]; then
      git status --short
    else
      echo "(clean)"
    fi
    echo

    echo "=== UNTRACKED FILES ==="
    untracked="$(git ls-files --others --exclude-standard)"
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
    echo

    echo "=== CHANGED FILES (stat) ==="
    git diff --stat "$range"
    echo

    detect_tests
    echo

    echo "=== PATCH ==="
    git diff "$range"
    ;;

  *)
    echo "ERROR: unknown mode '$MODE' (use: state | diff <base> <head>)" >&2
    exit 1
    ;;
esac
