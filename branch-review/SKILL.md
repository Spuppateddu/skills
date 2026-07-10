---
name: branch-review
description: Code-review a git diff. By default reviews everything the current branch would land — its commits AND its uncommitted work (staged, unstaged, untracked) as one target — or the diff between two branches the user picks. Tech-agnostic. Checks security, type safety, slow/N+1 queries and other inefficiencies, duplicated code, over-long or pointless comments, and missing tests (only when the repo has a test suite). Reports findings graded LOW/MEDIUM/HIGH/CRITICAL with color markers. Use when the user says e.g. "review my branch", "code review the diff", "review my changes before I push", "review the diff between X and Y".
---

# branch-review

Review a git diff for real problems and report them graded by severity. The skill
decides *what* to review from git state, then reviews *only the diff* — added and
changed lines — not the whole codebase.

Paths below are relative to this skill folder, so the skill works wherever installed.
The helper script needs only `git`.

## Step 1 — review the whole branch by default

"Review my branch" means **everything the branch would land**: its commits *and* the work
still sitting in the working tree. Committed, staged, unstaged and untracked files are one
review target, not a menu. Never review only the commits and call the branch reviewed.

Unless the user explicitly asked to compare two other branches, run:

```bash
bash "$(dirname "$0")/scripts/review_context.sh" branch
```

With no base it auto-detects the trunk (`origin/HEAD`, else `origin/main`, `origin/master`,
`main`, `master`, `develop`; on the trunk itself it falls back to the upstream so unpushed
commits are still covered). Pass a base explicitly to override:
`... branch <base>`.

It prints, in order: the resolved base and merge-base, the commits on the branch, the
working-tree status, the test-suite verdict, then **two patches** — one for tracked files
spanning committed + staged + unstaged changes, one presenting untracked files as
additions. Together they are the material to review.

If the auto-detected base looks wrong (branch cut from a release branch, unusual trunk
name), say which base you used and ask before reviewing against it.

Skip untracked files that are clearly generated, vendored, or build output — lockfiles,
`dist/`, `node_modules/`, minified bundles. Large untracked files are listed as SKIPPED by
the script rather than dumped; only read one if it's plausibly hand-written source.

Run `state` instead when you just need to inspect the situation without a patch (current
branch, detected base, uncommitted changes, untracked files, unpushed commits, test suite).

## Step 2 — the two-branch case

Only when the user names two branches to compare ("review the diff between X and Y"):

```bash
bash "$(dirname "$0")/scripts/review_context.sh" diff <base> <head>
```

This emits the review range, a changed-file stat, the test-suite verdict, and the full
patch. It uses a three-dot range (`base...head`) by default so you see only what `head`
introduces relative to the merge-base — not unrelated commits on `base`. Append
`--two-dot` as a 4th argument if the user wants a literal `base..head` comparison.

This mode covers **committed content only**. If `<head>` is the checked-out branch and the
tree is dirty, the script prints a warning listing the excluded changes — surface that to
the user and offer to rerun in `branch` mode.

If a patch is large, read the changed files for fuller context, but keep every finding
anchored to a line the diff actually adds or modifies.

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
