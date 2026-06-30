---
name: branch-review
description: Code-review a git diff — either the current branch's uncommitted/unpushed work, or the diff between two branches the user picks. Tech-agnostic. Checks security, type safety, slow/N+1 queries and other inefficiencies, duplicated code, over-long or pointless comments, and missing tests (only when the repo has a test suite). Reports findings graded LOW/MEDIUM/HIGH/CRITICAL with color markers. Use when the user says e.g. "review my branch", "code review the diff", "review my changes before I push", "review the diff between X and Y".
---

# branch-review

Review a git diff for real problems and report them graded by severity. The skill
decides *what* to review from git state, then reviews *only the diff* — added and
changed lines — not the whole codebase.

Paths below are relative to this skill folder, so the skill works wherever installed.
The helper script needs only `git`.

## Step 1 — pick the review target

Run the context script (no args = `state`) to see the current branch's situation:

```bash
bash "$(dirname "$0")/scripts/review_context.sh" state
```

It prints: current branch, uncommitted changes (working tree + index), untracked
files, unpushed commits (vs the upstream), and whether a test suite exists.

Decide from that output:

- **Uncommitted or untracked changes exist** → ASK the user: "You have uncommitted
  changes on `<branch>` — review those?" If yes, the review target is the working-tree
  diff: `git diff HEAD` plus any untracked files (read them in full with the file
  tools — they have no diff). Do not review untracked files that are clearly generated
  or vendored.
- **Tree is clean but there are unpushed commits** → ASK: "Branch `<branch>` is ahead
  of `<upstream>` by N commits — review those?" If yes, the target is
  `git diff <upstream>..HEAD`.
- **Everything committed and pushed (clean tree, not ahead)** → ASK the user for the
  TWO branches to compare. Never assume them. Then go to Step 2.

If the user already named what to review (e.g. "review my changes" or "review X vs Y"),
skip the questions and act on it.

## Step 2 — get the diff

For a two-branch comparison, run:

```bash
bash "$(dirname "$0")/scripts/review_context.sh" diff <base> <head>
```

This emits the review range, a changed-file stat, the test-suite verdict, and the full
patch. It uses a three-dot range (`base...head`) by default so you see only what `head`
introduces relative to the merge-base — not unrelated commits on `base`. Append
`--two-dot` as a 4th argument if the user wants a literal `base..head` comparison.

The output of this script (or `git diff HEAD` for uncommitted work) IS the material to
review. If the patch is large, read the changed files for fuller context, but keep every
finding anchored to a line the diff actually adds or modifies.

## Step 3 — review

Examine the diff against each axis below. Report a finding only when it concerns
changed/added lines and you can point to the specific file and line. Prefer fewer,
real findings over a long list of speculation — every finding must name a concrete
failure or a concrete improvement, not a vague worry.

1. **Security** — injection (SQL/command/template), missing authz/authn checks, unsafe
   deserialization, secrets or credentials committed, unescaped output (XSS), path
   traversal, SSRF, weak crypto, unvalidated input crossing a trust boundary.
2. **Type safety** — if the language/project is statically typed or has a type checker
   (TypeScript, mypy, PHPStan/Psalm, Go, Rust, etc.), flag type errors the diff
   introduces: wrong/loose types, unchecked nulls/undefined, unsafe casts, `any`
   escapes. If a type-check command is obvious (`tsc --noEmit`, `mypy`, `phpstan`),
   you may run it and report failures the diff caused. Skip this axis for untyped code.
3. **Performance** — N+1 queries (a query inside a loop / per-row lookups that should be
   eager-loaded or batched), queries missing a usable index, `SELECT *` of fat tables,
   unbounded result sets / missing pagination, work repeated inside a loop that could be
   hoisted, O(n²) over large inputs, sync I/O on a hot path.
4. **Duplicated code** — added code that restates logic already present elsewhere.
   Before flagging, search the repo for an existing function/component/util that should
   be reused. Point to the existing thing to reuse.
5. **Comments** — comments longer than ~2 lines, comments that just restate the code,
   commented-out code, or stale comments the change made wrong. Flag them as cleanups.
6. **Missing tests** — ONLY if Step 1/2 reported `TEST_SUITE: yes`. Flag new
   logic/branches/bugfixes with no accompanying test. Name the behavior that should be
   covered. If `TEST_SUITE: none detected`, skip this axis entirely — do not suggest
   adding a test framework.

## Step 4 — report

Group findings by severity, most severe first, using these markers so they're easy to
scan in a terminal:

- 🔴 **CRITICAL** — exploitable security hole, data loss/corruption, or a guaranteed
  break in production.
- 🟠 **HIGH** — real bug, a query that will degrade badly under load, or a clear
  vulnerability needing input to trigger.
- 🟡 **MEDIUM** — likely-bug, meaningful inefficiency, notable duplication, or missing
  test for important logic.
- 🔵 **LOW** — style, comment cleanups, minor duplication, nits.

Grade by *impact × likelihood*, not by category — a comment nit is always LOW; an
unauthenticated admin endpoint is always CRITICAL.

Format each finding as one entry:

```
🟠 HIGH — N+1 query in the order loop
app/Services/OrderReport.php:42
Each order triggers a separate `customer()` lookup; 500 orders → 500 queries.
Fix: eager-load with `->with('customer')` on the base query (line 30).
```

End with a one-line tally, e.g. `2 critical · 1 high · 3 medium · 4 low`. If a whole
axis was skipped (untyped project, no test suite), say so in a single line so the user
knows it was a deliberate skip, not an oversight. If nothing was found on an axis, don't
pad the report — silence on an axis means clean.
