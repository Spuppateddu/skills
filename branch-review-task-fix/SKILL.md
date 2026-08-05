---
name: branch-review-task-fix
description: Take ONE task/finding from a `branch-review` report (🔴/🟠/🟡 severity, file:line, claim, suggested fix) and work out whether it is a real problem or a hallucination. Reads the actual code around the line, checks the claimed mechanism really exists, re-grades the severity, then explains in plain language what breaks, when it breaks and who it hurts, and proposes concrete fixes. Tech-agnostic; explains only — it does not edit files unless asked. Use when the user says e.g. "fix this review task", "check task 2", "is this finding real?", "explain this review finding", "how do I fix this one", or pastes a single graded finding from a review.
---

# branch-review-task-fix

A review report is a list of *claims*. This skill takes **one** claim and turns it into a
verdict the user can act on: real or not, why it matters in plain words, and how to fix it.

Reviews hallucinate. They flag N+1 queries on loops that run twice, missing auth on routes
already behind middleware, unescaped output a template engine escapes for you. The whole
point of this skill is to **re-derive the problem from the code**, never from the finding's
own reasoning.

Paths below are relative to this skill folder, so it works wherever installed. The helper
script needs only `git` and `awk`.

## Step 1 — pin down which task

"Task", "finding" and "issue" all mean the same thing here: one graded entry from a review
report. Input is a single one, in the `branch-review` shape:

```
🟠 HIGH — N+1 query in the order report loop

Where
  app/Services/OrderReport.php:42, in OrderReport::buildReport()
      foreach ($orders as $order) { ... $order->customer->name ... }

What
  `$orders` is fetched at line 30 without its `customer` relation, so reading
  `$order->customer` inside the loop lazy-loads it — one extra SELECT per order.

If not fixed
  A tenant with 500 orders turns one request into 501 queries instead of 2.

Fix
  Eager-load at line 30: `Order::with('customer')->where(...)`.
```

Pull out five things: **severity**, **file:line**, **the claim** (What), **the predicted
consequence** (If not fixed), and **the proposed fix**. Each is judged separately — a
finding can name a real defect, overstate its consequence, and propose a wrong fix, all at
once. Older or hand-written findings may be a terse one-liner instead; that's fine, just
extract whichever of the five are present.

If the user pasted several findings, triage them one at a time, most severe first, and say
that's what you're doing. If they referred to a finding from an earlier review in this
conversation ("check number 2"), use that text — don't ask them to paste it again. If
there's no file:line anywhere, ask for one; without a location nothing can be verified.

## Step 2 — gather ground truth

```bash
bash "$(dirname "$0")/scripts/finding_context.sh" <file>:<line> [radius] [base]
```

It resolves the path (even if the review wrote it oddly, or it's a bare basename), prints
a numbered code window with the reported line marked `>>`, says whether that line is
**actually part of the branch's change** vs the base, blames it, shows the enclosing
declaration and the file's recent history. `radius` defaults to 25 lines.

Three of its outputs kill a finding on their own:

- **NOT FOUND** — the file doesn't exist. Hallucination, unless the path is just written
  differently (check the candidates it lists).
- **line past the end of file** — the location is invented. Look for the described code
  elsewhere in the file before believing anything.
- **PRE-EXISTING / UNCHANGED LINE** — the code is real but the branch didn't touch it. Say
  so: it's out of scope for a diff review even if the code is genuinely bad. Note it as a
  pre-existing issue, don't grade it as part of the branch.

Then read wider. The code window is a starting point, not the evidence — open the whole
file, follow the functions it calls, and grep the repo for the guard that would make the
finding moot. Read framework config, middleware, base classes and decorators; that's where
the protections a reviewer misses usually live.

## Step 3 — decide: real, or hallucination

Verify **the mechanism**, not the vibe. For the claim to stand, every link in its chain has
to exist in the code you just read. Work through the ones that apply:

- **N+1 / performance** — is the call *really* inside a loop? Is the collection actually
  large, or bounded to a handful of rows? Is there already eager loading, caching, or a
  batch fetch upstream? Does the ORM lazy-load here at all?
- **Missing auth/authz** — is the route already behind middleware, a guard, a decorator, a
  base controller, or a gateway rule? Search the router/config, not just the handler.
- **Injection** — does user input genuinely reach the sink unparameterised? Trace the
  variable back to its origin. A bound parameter, a whitelist, or a typed cast upstream
  ends the claim.
- **XSS / unescaped output** — does the template engine auto-escape? Is the context HTML,
  attribute, JS or URL? Auto-escaping fails in some of those and not others.
- **Null / type error** — can the value actually be null *on this path*? Look for the
  earlier guard, the non-null default, the schema constraint.
- **Duplication** — open the code it says to reuse. Is it truly the same behavior, or does
  it just look alike?
- **Missing test** — does a test already cover this behavior under another name? Grep the
  test suite before agreeing.

Then land on one of three verdicts:

- ✅ **REAL** — the mechanism exists and the consequence follows. Say what triggers it.
- ⚠️ **PARTLY REAL** — something is off, but not what the finding claims, or not at that
  severity. Correct it: restate the actual problem and re-grade it.
- ❌ **NOT A PROBLEM** — the chain breaks somewhere. Name the exact link that breaks and
  point at the code that breaks it (`file:line`). "I couldn't reproduce the reviewer's
  reasoning" is not a verdict — find what they mistook.

Re-grade severity yourself using *impact × likelihood*. Reviews inflate. The scale is
🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM — there is no LOW tier. If the loop runs over 3 config
rows, an N+1 falls *below* MEDIUM: say so, call it not worth fixing, and close it. If the
endpoint is public and unauthenticated, it's 🔴 CRITICAL whatever the report said. State
the change and why.

When you close a finding — ❌ NOT A PROBLEM, below MEDIUM, or the user decides to keep the
code as it is — say so explicitly and tell the user it should be closed in the review
ledger, so `branch-review` doesn't raise it again next round:

```bash
bash <path-to>/branch-review/scripts/review_ledger.sh close <id> WONTFIX "<one-line reason>"
```

Findings carry their ledger id when the report included one. If it doesn't, `show` lists
them. Closing is what stops the review → fix → re-flag loop; don't skip it.

Never confirm a finding because it sounds plausible or because the reviewer was confident.
If after reading you genuinely can't tell — the code path depends on runtime data you can't
see — say so, say precisely what would settle it (a query log, a specific input, a table's
row count), and give the verdict as conditional.

## Step 4 — explain it in plain language

This is the part the user asked for. Assume they're competent but haven't got this code
loaded in their head. No jargon unless you define it in the same sentence.

Cover, in this order:

1. **What the code does now** — one or two sentences, in words, not code.
2. **What goes wrong** — the concrete failure. Name it: "the page takes 8 seconds",
   "anyone with the URL can read another customer's invoice", "the job crashes on the
   first row with no email".
3. **When it happens** — the trigger. Every request? Only with 500+ rows? Only if an
   attacker crafts the input? A problem that needs a hostile user is different from one
   that fires on Tuesday.
4. **Who it hurts** — users, the database, on-call, the security posture.

Use real numbers from the code where you can (row counts, loop bounds, timeouts, limits).
"500 orders → 501 queries → ~4s of database time" beats "this is inefficient". If the
numbers are unknown, say what you assumed.

Skip this whole step's drama when the verdict is ❌ — a false alarm gets a short, clear
explanation of what the reviewer misread, and then you're done.

## Step 5 — suggest fixes

Give the **primary fix** first: the smallest change that removes the cause, with a real
code snippet using this codebase's own idioms, naming and helpers — not generic pseudocode.
Show the before/after lines and say where they go.

Then, when they genuinely apply:

- **A cheaper alternative** — if the primary fix is invasive, the 80% version.
- **What it might break** — behavior that depends on the current shape, callers to update.
- **How to verify** — the command, the test to write, the query log to check. If the repo
  has a test suite, name the test and what it should assert; if it has none, don't suggest
  adding a framework.

Judge the finding's own proposed fix too. If it's right, say so and move on. If it's wrong,
incomplete, or fixes a symptom, say why and replace it.

**Explain by default; don't edit.** Producing the patch is a separate ask — offer it at the
end ("want me to apply this?") and wait.

## Step 6 — report

One finding, one block, in this shape:

```
🟠 HIGH — N+1 query in the order loop
app/Services/OrderReport.php:42

VERDICT: ✅ REAL — re-graded 🟠 HIGH → 🟡 MEDIUM

What's happening
  `buildReport()` loops over the orders it just fetched and reads `$order->customer`
  inside the loop. That property isn't loaded, so each pass fires its own SELECT.

Why it's a problem
  A 500-order report becomes 501 database round-trips instead of 2. On the reports
  page that's roughly 3-4 extra seconds, all of it holding a connection open. It
  gets worse linearly as a tenant's order history grows — nothing caps it.

When it fires
  Every call to the reports endpoint. No special input needed.

Why MEDIUM, not HIGH
  The endpoint is admin-only and hit a few times a day, and the query itself is
  indexed — slow, not dangerous.

Fix
  Eager-load the relation on the base query, at line 30:

    - $orders = Order::where('tenant_id', $tenant)->get();
    + $orders = Order::with('customer')->where('tenant_id', $tenant)->get();

  Two queries total, regardless of order count. Nothing else changes — the loop
  body stays as it is.

Verify
  Wrap the endpoint in `DB::listen()` (or run it under Telescope) and confirm the
  query count drops from ~501 to 2. `tests/Feature/OrderReportTest.php` already
  hits this endpoint; assert the count there.
```

Adapt the section list to the finding — a comment nit doesn't need "when it fires". Drop
sections rather than padding them with filler. If the verdict is ❌ **NOT A PROBLEM**, the
whole block is: the finding, the verdict, the one thing that makes it wrong with its
`file:line`, and a sentence on what the reviewer likely confused it with.

If you triaged several findings, end with a one-line tally of verdicts, e.g.
`3 real · 1 partly real · 2 false alarms`.
