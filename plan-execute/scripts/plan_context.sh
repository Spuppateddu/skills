#!/usr/bin/env bash
#
# Gather the context a plan-driven implementation session needs. Two modes:
#
#   plan_context.sh status <plan.md>
#       Report three things, in order:
#         1. WHERE WE ARE  — branch, last commits, uncommitted work.
#         2. STACKS        — every backend/frontend project found (PHP, Python,
#                            JS/TS, Go, Rust, Ruby), each with the command to
#                            run its tests (whole suite + a single focused test)
#                            and its formatter/linter.
#         3. PLAN PROGRESS — checkbox tally, every task with its state, and
#                            the next unchecked task to pick up.
#
#   plan_context.sh stacks
#       Sections 1 and 2 only, with no plan file. Used when AUTHORING a plan
#       (see the plan-write skill), before any plan file exists.
#
# Monorepo-aware: a repo with backend/ and frontend/ reports BOTH stacks, so a
# plan spanning the two knows which suite covers which task. Detection walks up
# to 4 levels deep, skipping node_modules/ vendor/ dist/ build/ .venv/.
#
# The plan file is never modified by this script — it only reads it. Resuming a
# half-done plan is the normal case, so this is safe to re-run at any time.
#
# bash 3.2 compatible (macOS default). No external deps beyond git and awk.
#
set -euo pipefail

MODE="${1:-status}"
PLAN="${2:-}"

case "$MODE" in
  status)
    [ -n "$PLAN" ] || { echo "ERROR: usage: plan_context.sh status <plan.md>" >&2; exit 1; }
    [ -f "$PLAN" ] || { echo "ERROR: plan file not found: $PLAN" >&2; exit 1; }
    ;;
  stacks) ;;
  *) echo "ERROR: unknown mode '$MODE' (use: status <plan.md> | stacks)" >&2; exit 1 ;;
esac

FOUND_TESTS=0   # flipped to 1 by any stack that can actually run tests

# Find manifests up to 4 levels deep, ignoring dependency and build dirs.
find_manifest() {
  find . -maxdepth 4 \
    \( -name node_modules -o -name vendor -o -name .git -o -name dist \
       -o -name build -o -name .venv -o -name venv -o -name target \) -prune \
    -o -name "$1" -print 2>/dev/null | sort
}

# --- git state, mono-repo AND multi-repo ------------------------------------
# Handles both layouts:
#   mono : one repo at the root, backend/ and frontend/ inside it.
#   multi: a plain working folder holding backend/ and frontend/ as SEPARATE
#          clones, each with its own .git, branch and dirty state.
# A submodule's .git is a file, not a dir, so match both (-name .git, no -type).
find_repos() {
  find . -maxdepth 4 \
    \( -name node_modules -o -name vendor -o -name dist -o -name build \
       -o -name .venv -o -name venv -o -name target \) -prune \
    -o -name .git -prune -print 2>/dev/null | sort
}

report_repo() {
  d="$1"
  echo "  repo: $(label_dir "$d")"
  if br="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
    echo "    branch: $br"
    echo "    recent: $(git -C "$d" log --oneline -1 2>/dev/null || echo '(no commits yet)')"
  else
    echo "    branch: (no commits yet)"
  fi
  st="$(git -C "$d" status --porcelain 2>/dev/null || true)"
  if [ -n "$st" ]; then
    echo "    uncommitted:"
    printf '%s\n' "$st" | sed 's/^/      /'
  else
    echo "    uncommitted: (clean)"
  fi
  return 0
}

report_repos() {
  n=0
  for g in $(find_repos); do
    report_repo "$(dirname "$g")"
    n=$((n + 1))
  done
  if [ "$n" -eq 0 ]; then
    echo "  (no git repository found — cannot report branch state)"
  elif [ "$n" -gt 1 ]; then
    echo
    echo "  MULTI-REPO: $n repositories. Each has its OWN branch and its own commits."
    echo "  Match every plan task to its repo; never assume one branch covers both."
  fi
  echo
  return 0
}

has()  { [ -f "$1" ]; }
# grep without tripping `set -e` when there is no match
greps() { grep -q "$1" "$2" 2>/dev/null; }

label_dir() { d="${1#./}"; [ "$d" = "." ] && echo "(repo root)" || echo "$d"; }

# Print the "checks:" line only when something was detected. Every emit_*
# function MUST end with `return 0` — a trailing failed test would otherwise
# make the function return non-zero and `set -e` would kill the whole report.
print_checks() {
  [ -n "$1" ] || return 0
  echo "    checks:  $(printf '%s' "$1" | sed 's/^ *//; s/;[ ]*$//; s/;[ ]*/  ·  /g')"
}

# --- JS / TS ---------------------------------------------------------------
emit_js() {
  dir="$1"; pkg="$dir/package.json"

  pm=npm
  has "$dir/pnpm-lock.yaml" && pm=pnpm
  has "$dir/yarn.lock"      && pm=yarn
  has "$dir/bun.lockb"      && pm=bun

  kind="JS"
  has "$dir/tsconfig.json" && kind="TS"
  for fw in next nuxt vite react vue svelte angular; do
    greps "\"$fw\"" "$pkg" && { kind="$kind/$fw"; break; }
  done
  greps '"express"' "$pkg" && kind="$kind/express"
  greps '"nestjs\|@nestjs' "$pkg" && kind="$kind/nest"

  echo "  [$kind] $(label_dir "$dir")"

  runner=""
  greps '"vitest"' "$pkg" && runner=vitest
  [ -z "$runner" ] && greps '"jest"' "$pkg" && runner=jest
  [ -z "$runner" ] && { has "$dir/vitest.config.ts" || has "$dir/vitest.config.js"; } && runner=vitest
  [ -z "$runner" ] && { has "$dir/jest.config.ts"   || has "$dir/jest.config.js";   } && runner=jest

  has_script=0
  greps '"test"[[:space:]]*:' "$pkg" && has_script=1
  if [ "$has_script" -eq 1 ]; then
    echo "    tests:   $pm test"
    FOUND_TESTS=1
  fi
  case "$runner" in
    vitest) echo "    focused: npx vitest run <path/to/file.test.ts>"; FOUND_TESTS=1 ;;
    jest)   echo "    focused: npx jest <path/to/file.test.ts>";       FOUND_TESTS=1 ;;
    *)      [ "$has_script" -eq 1 ] || echo "    tests:   (none — no \"test\" script, no jest/vitest)" ;;
  esac

  checks=""
  if greps '"eslint"' "$pkg" || has "$dir/eslint.config.js" || has "$dir/.eslintrc.json" || has "$dir/.eslintrc.cjs"; then
    checks="$checks npx eslint .;"
  fi
  if greps '"prettier"' "$pkg" || has "$dir/.prettierrc" || has "$dir/.prettierrc.json"; then
    checks="$checks npx prettier --check .;"
  fi
  if greps '"@biomejs/biome"' "$pkg" || has "$dir/biome.json"; then
    checks="$checks npx biome check .;"
  fi
  has "$dir/tsconfig.json" && checks="$checks npx tsc --noEmit;"
  print_checks "$checks"
  return 0
}

# --- PHP -------------------------------------------------------------------
emit_php() {
  dir="$1"; cj="$dir/composer.json"

  kind="PHP"
  has "$dir/artisan" && kind="PHP/Laravel"
  has "$dir/bin/console" && kind="PHP/Symfony"

  echo "  [$kind] $(label_dir "$dir")"

  if has "$dir/vendor/bin/pest" || greps '"pestphp/pest"' "$cj"; then
    if has "$dir/artisan"; then
      echo "    tests:   php artisan test"
      echo "    focused: php artisan test --filter=<TestName>"
    else
      echo "    tests:   vendor/bin/pest"
      echo "    focused: vendor/bin/pest --filter=<TestName>"
    fi
    FOUND_TESTS=1
  elif has "$dir/phpunit.xml" || has "$dir/phpunit.xml.dist"; then
    if has "$dir/artisan"; then
      echo "    tests:   php artisan test"
      echo "    focused: php artisan test --filter=<TestName>"
    else
      echo "    tests:   vendor/bin/phpunit"
      echo "    focused: vendor/bin/phpunit --filter=<TestName>"
    fi
    FOUND_TESTS=1
  else
    echo "    tests:   (none — no phpunit.xml, no pest)"
  fi

  checks=""
  if has "$dir/vendor/bin/pint" || greps '"laravel/pint"' "$cj"; then
    checks="$checks vendor/bin/pint;"
  fi
  greps '"friendsofphp/php-cs-fixer"' "$cj" && checks="$checks vendor/bin/php-cs-fixer fix;"
  if greps '"phpstan/phpstan"' "$cj" || greps '"larastan/larastan"' "$cj" || has "$dir/phpstan.neon"; then
    checks="$checks vendor/bin/phpstan analyse;"
  fi
  greps '"vimeo/psalm"' "$cj" && checks="$checks vendor/bin/psalm;"
  print_checks "$checks"
  return 0
}

# --- Python ----------------------------------------------------------------
emit_py() {
  dir="$1"; py="$dir/pyproject.toml"; req="$dir/requirements.txt"

  # a dependency named in pyproject.toml OR requirements.txt
  dep() { greps "$1" "$py" || greps "$1" "$req"; }

  kind="Python"
  if has "$dir/manage.py"; then kind="Python/Django"
  elif dep 'fastapi';      then kind="Python/FastAPI"
  elif dep 'flask\|Flask'; then kind="Python/Flask"
  fi

  echo "  [$kind] $(label_dir "$dir")"

  if has "$dir/pytest.ini" || has "$dir/tox.ini" || greps '\[tool.pytest' "$py" || dep 'pytest'; then
    echo "    tests:   pytest"
    echo "    focused: pytest <path/to/test_x.py::test_name>"
    FOUND_TESTS=1
  elif has "$dir/manage.py"; then
    echo "    tests:   python manage.py test"
    echo "    focused: python manage.py test <app.tests.TestCase.test_name>"
    FOUND_TESTS=1
  elif [ -n "$(find "$dir" -maxdepth 2 \( -name 'test_*.py' -o -name '*_test.py' \) 2>/dev/null | head -1)" ]; then
    echo "    tests:   python -m unittest discover  (test files, but no pytest config)"
    FOUND_TESTS=1
  else
    echo "    tests:   (none detected)"
  fi

  checks=""
  if dep 'ruff' || has "$dir/ruff.toml"; then
    checks="$checks ruff check .;ruff format --check .;"
  fi
  dep 'black' && checks="$checks black --check .;"
  dep 'mypy'  && checks="$checks mypy .;"
  has "$dir/.flake8" && checks="$checks flake8;"
  print_checks "$checks"
  return 0
}

# --- Go / Rust / Ruby ------------------------------------------------------
emit_go() {
  echo "  [Go] $(label_dir "$1")"
  echo "    tests:   go test ./..."
  echo "    focused: go test ./<pkg> -run <TestName>"
  echo "    checks:  gofmt -l .  ·  go vet ./..."
  FOUND_TESTS=1
  return 0
}
emit_rust() {
  echo "  [Rust] $(label_dir "$1")"
  echo "    tests:   cargo test"
  echo "    focused: cargo test <test_name>"
  echo "    checks:  cargo fmt --check  ·  cargo clippy"
  FOUND_TESTS=1
  return 0
}
emit_ruby() {
  dir="$1"
  echo "  [Ruby] $(label_dir "$dir")"
  if [ -d "$dir/spec" ]; then
    echo "    tests:   bundle exec rspec"
    echo "    focused: bundle exec rspec <path>:<line>"
    FOUND_TESTS=1
  elif [ -d "$dir/test" ]; then
    echo "    tests:   bundle exec rake test"
    FOUND_TESTS=1
  else
    echo "    tests:   (none detected)"
  fi
  return 0
}

detect_stacks() {
  found_any=0
  py_seen=""   # space-delimited dirs already emitted as Python

  for m in $(find_manifest package.json);  do emit_js   "$(dirname "$m")"; found_any=1; done
  for m in $(find_manifest composer.json); do emit_php  "$(dirname "$m")"; found_any=1; done

  # Python: pyproject.toml first, then projects that have no pyproject.
  # A dir can match several markers (Django has manage.py AND pytest.ini) — emit once.
  for m in $(find_manifest pyproject.toml) $(find_manifest manage.py) \
           $(find_manifest pytest.ini) $(find_manifest setup.py) $(find_manifest requirements.txt); do
    d="$(dirname "$m")"
    case " $py_seen " in *" $d "*) continue ;; esac
    py_seen="$py_seen $d"
    emit_py "$d"; found_any=1
  done

  for m in $(find_manifest go.mod);     do emit_go   "$(dirname "$m")"; found_any=1; done
  for m in $(find_manifest Cargo.toml); do emit_rust "$(dirname "$m")"; found_any=1; done
  for m in $(find_manifest Gemfile);    do emit_ruby "$(dirname "$m")"; found_any=1; done

  [ "$found_any" -eq 0 ] && echo "  (no recognized project manifest found)"
  echo
  if [ "$FOUND_TESTS" -eq 1 ]; then
    echo "TEST_SUITE: yes — TDD and per-feature tests are REQUIRED"
    echo "  Run the suite of the stack the task touches. Verify these commands against"
    echo "  the repo's CI config (.github/workflows) before trusting them."
  else
    echo "TEST_SUITE: none detected — SKIP every test rule, do NOT add a test framework"
  fi
}

# --- plan checklist parsing ------------------------------------------------
# A task is a markdown list item with a checkbox: "- [ ] ..." or "- [x] ...".
parse_plan() {
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^[ \t]*[-*][ \t]+\[.\][ \t]/ {
      box = $0
      sub(/^[ \t]*[-*][ \t]+\[/, "", box)
      mark = substr(box, 1, 1)
      text = $0
      sub(/^[ \t]*[-*][ \t]+\[.\][ \t]+/, "", text)
      if (mark == "x" || mark == "X") {
        done++
        printf "  [x] L%-4d %s\n", NR, trim(text)
      } else {
        # not done: plain "[ ]", but also "[~]" (in progress) and "[!]" (blocked).
        # Echo the real marker so a resumed session sees where work was left.
        todo++
        if (nextln == 0) { nextln = NR; nexttext = trim(text) }
        printf "  [%s] L%-4d %s\n", mark, NR, trim(text)
      }
      next
    }
    END {
      total = done + todo
      if (total == 0) {
        print "PLAN_CHECKLIST: none — the plan has no \"- [ ]\" tasks yet"
        print "  → normalize it first: turn each planned step into a checkbox task."
        exit 0
      }
      printf "\nPROGRESS: %d/%d done, %d remaining\n", done, total, todo
      if (todo == 0) {
        print "NEXT: (nothing) — every task is checked off. Verify, then report done."
      } else {
        printf "NEXT: line %d — %s\n", nextln, nexttext
      }
    }
  ' "$1"
}

echo "=== WHERE WE ARE ==="
report_repos

echo "=== STACKS ==="
detect_stacks

[ "$MODE" = "stacks" ] && exit 0

echo
echo "=== PLAN: $PLAN ==="
parse_plan "$PLAN"
