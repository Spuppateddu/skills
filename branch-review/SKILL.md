---
name: branch-review
description: Code-review a git diff. By default reviews everything the current branch would land — its commits AND its uncommitted work (staged, unstaged, untracked) as one target — or the diff between two branches the user picks. Tech-agnostic. Checks security, type safety, duplicated code, missing tests (only when the repo has a test suite), regressions — code that undoes an earlier fix, which the net diff alone cannot show, so it reads git history to learn why a line exists before judging its removal — and speed: it benchmarks, times or query-counts whatever the diff makes hot instead of only eyeballing it, and reports the base-vs-branch delta. Reports only findings worth acting on, graded MEDIUM/HIGH/CRITICAL with color markers — style nits and preferences are never reported. Each finding is self-contained (where / what / what it causes if unfixed / how to fix) so it can be pasted to another agent to fix. Keeps a per-branch ledger of what it already said, so repeated reviews converge instead of re-flagging or undoing earlier fixes. Use when the user says e.g. "review my branch", "code review the diff", "review my changes before I push", "review the diff between X and Y", "check I didn't break something we already fixed".
---

# branch-review

Review a git diff for real problems and report them graded by severity. The skill
decides *what* to review from git state, then reviews *only the diff* — added and
changed lines — not the whole codebase.

Two hard rules shape everything below:

- **Only actionable severities.** CRITICAL, HIGH, MEDIUM. Style, nits, comment
  cleanups and preferences are not reported at all — see Step 5.
- **The review must converge.** A second or third review of the same branch must
  shrink, never churn. A per-branch ledger enforces that — see Step 0 and Step 6.

Git history is read as *context*, not as review scope: it tells you why a changed line
exists and whether the branch undoes a fix that already landed. Findings stay anchored to
lines the diff touches.

Paths below are relative to this skill folder, so the skill works wherever installed.
The helper scripts need only `git`.

## Step 0 — open the round, read what you already said

Before anything else:

```bash
bash "$(dirname "$0")/scripts/review_ledger.sh" start
```

This bumps the round counter for the current branch and prints every finding this skill
has already reported on it, with its id, severity, location and status (`OPEN`, `FIXED`,
`WONTFIX`, `CONFLICT`, `STALE`). The ledger lives in `.git/branch-review/`, so it is never
committed and never appears in `git status`.

Read it before you review. It is the memory that stops the fix loop the user actually
hits: review → fix → review re-flags it (or asks to undo it) → fix again → forever.
Step 6 tells you exactly what to do with each prior entry.

If the user says the ledger is wrong or wants a clean slate ("review this from scratch"),
run `review_ledger.sh reset` and say you did.

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

## Step 3 — regression pass (always, before reviewing the diff)

A diff is the *net* result, and that hides two things. If commit 1 fixed a bug and commit 3
rewrote the same function without the guard, the range shows no trace of it — the fix is
simply gone. And a deleted line looks harmless until you learn it was added by a bugfix.
This is exactly how an agent's rewrite silently reopens something already fixed. Run:

```bash
bash "$(dirname "$0")/scripts/review_context.sh" history [base]
```

Same base auto-detection as Step 1; pass the same base you used there. A 3rd argument caps
how many changed line-ranges get a provenance lookup (default 40) — raise it for a big diff
if the run was fast. It prints three sections, each marking with `*` any commit whose
subject reads like a deliberate fix (fix, revert, security, race, crash, guard…):

- **Intra-branch churn** — files touched by more than one commit on the branch, with those
  commits. Where a later commit can undo an earlier one. For any file listed with a fix-ish
  commit followed by a later one, diff the two (`git diff <fix-commit> HEAD -- <file>`) and
  confirm the fix survived.
- **Prior history of the changed files** — what those files were already fixed for, before
  the branch existed.
- **Provenance of deleted/rewritten lines** — for each pre-existing range the branch removes
  or rewrites, the commits that last touched it.

Then, for every removed or rewritten line whose provenance is a fix-ish commit, read that
commit (`git show <hash>`) before accepting the change. The commit message and its test say
why the line was put there. Decide explicitly: is the change deliberately superseding that
fix (keeping the behavior another way), or did it drop the guard without noticing? The
second is a regression — report it, quoting the original fix commit.

This mode reads `HEAD` against the base, so in the two-branch case of Step 2 it applies only
when `<head>` is the checked-out branch. Otherwise check out `<head>` first, or say in the
report that the regression pass was skipped.

## Step 4 — review

Examine the diff against each axis below. Report a finding only when it concerns
changed/added lines and you can point to the specific file and line. Prefer fewer,
real findings over a long list of speculation — every finding must name a concrete
failure or a concrete cost, not a vague worry.

Three filters kill a candidate finding before it is ever written up:

- **No nits.** If it would grade LOW — style, naming, formatting, comment cleanups,
  minor duplication, "could be tidier" — drop it silently. Do not inflate it to MEDIUM
  to keep it. See Step 5.
- **No preferences.** If both the current code and your suggestion are defensible and
  you cannot name what breaks, it is taste, not a defect. Taste is what makes reviews
  oscillate: one round says "extract this", the next says "this indirection is
  pointless, inline it". Drop it.
- **Nothing the ledger already settled.** Step 6.

1. **Security** — injection (SQL/command/template), missing authz/authn checks, unsafe
   deserialization, secrets or credentials committed, unescaped output (XSS), path
   traversal, SSRF, weak crypto, unvalidated input crossing a trust boundary.
2. **Type safety** — if the language/project is statically typed or has a type checker
   (TypeScript, mypy, PHPStan/Psalm, Go, Rust, etc.), flag type errors the diff
   introduces: wrong/loose types, unchecked nulls/undefined, unsafe casts, `any`
   escapes. If a type-check command is obvious (`tsc --noEmit`, `mypy`, `phpstan`),
   you may run it and report failures the diff caused. Skip this axis for untyped code.
3. **Performance — read it, then measure it.** This axis is not satisfied by reading
   alone; see "Measure the speed" below.
   - *Static:* N+1 queries (a query inside a loop / per-row lookups that should be
     eager-loaded or batched), queries missing a usable index, `SELECT *` of fat tables,
     unbounded result sets / missing pagination, work repeated inside a loop that could
     be hoisted, O(n²) over large inputs, sync I/O on a hot path, an await inside a loop
     that could run concurrently, a regex or JSON parse rebuilt per iteration.
   - *Measured:* the actual wall-clock cost of what the diff changed.
4. **Duplicated code** — added code that restates logic already present elsewhere.
   Before flagging, search the repo for an existing function/component/util that should
   be reused. Point to the existing thing to reuse, and only when the duplication is real
   logic, not two lines that happen to look alike.
6. **Missing tests** — ONLY if Step 1/2 reported `TEST_SUITE: yes`. Flag new
   logic/branches/bugfixes with no accompanying test. Name the behavior that should be
   covered. If `TEST_SUITE: none detected`, skip this axis entirely — do not suggest
   adding a test framework.
7. **Regressions / undone fixes** — from Step 3: a guard, null check, bounds check,
   escaping, retry/idempotency check, `try`/`catch`, or workaround that a prior commit
   added on purpose and this branch drops or weakens; a test deleted or its assertions
   loosened; a later branch commit reverting an earlier one. Also flag a change that
   contradicts a fix-ish commit's intent even when the line itself survives. Cite the
   commit that introduced the thing being removed, and say what breaks again.

Stale or wrong comments are reported only when the comment states something untrue that
would mislead a maintainer into a bug — that is a MEDIUM defect, not a nit. Comment
length, tone and tidiness are never reported.

### Measure the speed

Reading a diff tells you where a bottleneck *could* be. Timing it tells you whether there
is one. For anything the diff makes hot — a command, an endpoint, a script, a build step,
a query, a hot function — get a real number before grading it.

Pick the cheapest measurement that produces one, in this order:

1. **The project's own benchmark or profiler**, if it has one (`pytest-benchmark`,
   `cargo bench`, `go test -bench`, `vitest bench`, `hyperfine`, Blackfire, Telescope,
   Django Debug Toolbar, `EXPLAIN ANALYZE`). Run it and quote the output.
2. **Time the thing directly** — run the changed CLI/script/test file under `time` (or
   `hyperfine` when it's installed and the run is short), a few times, and report the
   spread. A test file the diff touched is often the cheapest realistic harness.
3. **Count the work instead of timing it** when timing isn't possible: query count via
   the ORM's query log, `EXPLAIN` on the new query, iteration count from the loop bounds
   and the real row count (`SELECT count(*)`), bundle size delta, allocation count.
4. **Estimate from the code, and say it's an estimate** — only when 1–3 are all
   impossible. State the assumption you used (row count, payload size) so the user can
   correct it.

Rules for measuring:

- **Compare against the base.** A number on its own is not a finding. Where it's cheap,
  measure the same thing on the merge-base (`git stash` / a worktree at the base) and
  report the delta: "42 ms → 380 ms". A regression the diff introduced is HIGH; code
  that was already slow and stays slow is out of scope for a diff review.
- **Stay safe and local.** Read-only, local commands only. Never run a benchmark against
  production, never run load generators, never run migrations, seeds, or anything that
  writes to a shared database. If the only way to measure is unsafe or slow (minutes),
  don't — fall back to counting, and say why.
- **Say what you ran.** Quote the command and its output in the finding. An unverifiable
  number is worse than an honest estimate.
- **Report the absence too.** If nothing in the diff is on a hot path, say so in one line
  rather than inventing a benchmark.

If measuring would take real setup (a fixture, a seeded database, a harness that doesn't
exist), don't build it — report the static finding, say what measurement would settle it,
and offer to run it if the user sets it up.

## Step 5 — report

Group findings by severity, most severe first, using these markers so they're easy to
scan in a terminal:

- 🔴 **CRITICAL** — exploitable security hole, data loss/corruption, or a guaranteed
  break in production.
- 🟠 **HIGH** — real bug, a measured or certain performance regression, a query that
  will degrade badly under load, or a clear vulnerability needing input to trigger.
- 🟡 **MEDIUM** — likely-bug, meaningful inefficiency, notable duplication of real
  logic, or a missing test for important logic.

**There is no LOW tier.** Anything that would have graded LOW is not a finding: don't
report it, don't collect it in a "minor notes" section at the end, don't mention it in
passing. If the honest grade is LOW, the honest report is silence.

A regression inherits the severity of the bug it reopens: dropping a guard that a security
or data-corruption fix added is CRITICAL, never a nit.

The failure mode this creates is grade inflation — calling a nit MEDIUM so it survives.
A finding is MEDIUM only if you can finish the sentence "if nobody touches this, X will
happen" with something concrete. If X is "the code stays slightly less tidy", it's a nit.
Grade by *impact × likelihood*, not by category: an unauthenticated admin endpoint is
CRITICAL however small the diff; a shorter variable name is nothing at all.

### Each finding must survive being pasted on its own

The user copies findings out of this report one at a time and hands them to another agent
to fix, with no diff and no conversation attached. So every entry has to carry its own
context. Never write "see above", "same as the previous finding", "this file", "the loop
mentioned earlier", or a bare line number with no path — the reader of that block has none
of it. Repeat what's needed even if it appears three findings up.

Write four labelled sections, in this order:

- **Where** — `path/to/file.ext:LINE`, plus the enclosing function/class/component by name,
  and the quoted line(s) at fault. The fixer must be able to jump straight to the code.
- **What** — the defect itself, mechanically. What the code does, and why that's wrong.
  One short paragraph, plain language, no jargon you don't define.
- **If not fixed** — the concrete consequence. Name the failure and its trigger: what
  breaks, under what conditions, and who it hits. Use real numbers from the code (row
  counts, loop bounds, payload sizes) where you can.
- **Fix** — a specific proposal, in this codebase's own idioms and helpers, with the
  before/after lines and where they go. If the fix touches somewhere other than the
  reported line, give that location too. Add a one-line note on how to verify it.

Every fix must be **terminal**: once applied, this same review must have nothing left to
say there. Before writing the Fix section, check it three ways —

- Would the fixed code trip any axis in Step 4 (a new untested branch, a new duplicate,
  a slower path)? If yes, propose a different fix, or name the follow-up inside this same
  finding so it never becomes a second round.
- Does the fix undo something this diff deliberately introduced? Then either the diff's
  intent is wrong (say that outright, as one finding) or your fix is — don't file it as a
  small correction that the next round will reverse back.
- Is there exactly one right end state? "Either extract it or inline it, your call" is
  not a fix; it's an invitation to oscillate. Pick one and justify it.

```
🟠 HIGH [#7] — N+1 query in the order report loop

Where
  app/Services/OrderReport.php:42, in OrderReport::buildReport()
      foreach ($orders as $order) {
          $rows[] = $this->formatRow($order, $order->customer->name);
      }

What
  `$orders` is fetched at line 30 without its `customer` relation, so reading
  `$order->customer` inside the loop lazy-loads it — one extra SELECT per order.

If not fixed
  A tenant with 500 orders turns one request into 501 queries instead of 2. The
  reports endpoint spends ~3-4 extra seconds holding a database connection, and it
  degrades linearly as order history grows — nothing caps the loop.

Fix
  Eager-load the relation on the base query at line 30:

    - $orders = Order::where('tenant_id', $tenant)->get();
    + $orders = Order::with('customer')->where('tenant_id', $tenant)->get();

  The loop body is unchanged. Verify with `DB::listen()` around the endpoint: the
  query count should drop from ~501 to 2.
```

A regression finding additionally names, in **What**, the commit it undoes and what that
commit was for:

```
🔴 CRITICAL [#2] — reopens the double-charge bug fixed in c7de040

Where
  app/Services/Payment.php:12, in PaymentService::charge()
      $gateway->charge($order->total, $order->id);

What
  `refactor: simplify charge` (a8ced2a, on this branch) dropped the
  `if ($order->paid) return;` guard that c7de040 "fix: prevent double charge on
  retry" added, along with the test that covered it.

If not fixed
  A retried Stripe webhook — the exact case c7de040 was filed for — charges the
  customer twice. Silent: nothing in the flow detects the second charge.

Fix
  Restore the guard as the first statement of charge(), and restore
  tests/Payment/DoubleChargeTest.php from c7de040. Verify by replaying the same
  webhook payload twice: the second call must be a no-op.
```

Scale the prose to the finding — a small 🟡 MEDIUM gets one line per section, not a
paragraph. But keep all four sections and keep the location complete, every time.

For a performance finding, quote the measurement inside **If not fixed**: the command you
ran, the numbers, and the base-vs-branch delta if you have one. If you could only
estimate, label it an estimate and give the assumption.

End with a one-line tally, e.g. `1 critical · 2 high · 3 medium`. If a whole axis was
skipped (untyped project, no test suite, regression pass not possible, nothing on a hot
path to measure), say so in a
single line so the user knows it was a deliberate skip, not an oversight. If nothing was
found on an axis, don't pad the report — silence on an axis means clean.

## Step 6 — write the round to the ledger, and let it close things

The ledger from Step 0 is what makes the second review shorter than the first. Reconcile
it *before* you write the report, then record what you reported.

**For every entry already in the ledger**, decide which of these it is:

- **Defect gone from the diff** → `close <id> FIXED "<what fixed it>"`. Never re-report a
  FIXED entry. Mention it in one line: "#3 N+1 in OrderReport — fixed, verified".
- **Still present, still reported this round** → `bump <id>`, and note in the report that
  it's carried over from round N.
- **Still present, but already reported twice** (`seen:2` or more) → do not expand it
  again. `close <id> WONTFIX "reported 3 rounds, not addressed"` and list it as a single
  line under "Still open, not re-litigating". Three sightings is the cap: after that this
  skill has said all it usefully can, and repeating it is the loop.
- **The user declined it, or said it's intentional** → `close <id> WONTFIX "<their
  reason>"`. It never comes back, even if a later round would rediscover it.
- **The code it pointed at is gone or rewritten** → `close <id> STALE`.

**Reopening** is allowed only when the fix for a FIXED/WONTFIX entry introduced a genuine
CRITICAL or HIGH defect. Then file a *new* finding that names the old id ("re-opens #3 —
the eager-load added at line 30 now fetches 400k rows"), and say plainly it's a
regression from the earlier fix. Never quietly re-file the same MEDIUM.

**The flip-flop check.** Before writing any finding, ask: does my fix reverse a change
that was made to satisfy an earlier ledger entry? If yes, that is the loop the user hit —
stop. Record it with `close <old-id> CONFLICT "<new finding> would undo it"`, and instead
of a finding, write one paragraph naming both positions, saying which one you'd keep and
why, and asking the user to settle it. Two reviews disagreeing is a decision for them, not
a task to hand a fixing agent.

**Round cap.** `review_ledger.sh start` prints the round number and warns at round 4+.
From round 4 on, report only *new* CRITICAL and HIGH findings, close everything else in
the ledger, and end the report with a line saying the branch has been reviewed 4+ times
and further rounds will only look for critical regressions. A branch that keeps producing
MEDIUMs after three rounds needs a conversation, not another review.

**Record this round's findings before you print the report**, one call per finding you
decided to report:

```bash
bash "$(dirname "$0")/scripts/review_ledger.sh" add OPEN HIGH app/Services/OrderReport.php:42 "N+1 query in the order report loop"
```

It prints the id it assigned. Put that id in the finding's headline —
`🟠 HIGH [#7] — N+1 query in the order report loop` — so the user (and
`branch-review-task-fix`) can close exactly that entry after acting on it. Carried-over
findings keep the id they already have.

Give the same short title you used as the headline, so the next round can match them by
eye. Don't record findings you decided not to report — the ledger is a record of what the
user was told, not of everything you considered.
