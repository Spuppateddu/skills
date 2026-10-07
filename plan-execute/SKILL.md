---
name: plan-execute
description: Implement a markdown planning/spec file under strict ground rules — normalize the plan into a tracked checklist, then build it task by task in TDD order, ticking each task off in the file as it lands and running through the whole plan without pausing (stopping only when a human is needed, the user asks, or work is blocked), running the relevant tests (only where that project has a test suite). Builds strictly what the plan says, no invented scope. Tech-agnostic, backend and frontend: detects PHP (Laravel/Symfony/PHPUnit/Pest), Python (Django/FastAPI/Flask/pytest), JS/TS (Next/Vite/React/Vue/jest/vitest), Go, Rust and Ruby. Handles a monorepo and a working folder holding several separate clones (backend/ + frontend/), where the plan says what to do in each. Keeps plans in a gitignored `plan/` folder split into to-start / in-progress / done, works only on to-start or in-progress plans, and moves each plan to the right folder as it starts and finishes. Use when the user pastes or points at a plan/spec/roadmap markdown file and says e.g. "implement this plan", "execute this planning file", "start working through this spec", "continue the plan".
---

# plan-execute

Turn a markdown plan into working code, one task at a time and the whole plan in one run,
with the plan file itself as the source of truth for progress. The plan is a contract: build what it says, tick
off what you finish, prove it with tests.

Paths below are relative to this skill folder, so the skill works wherever installed.
The helper script needs only `git` and `awk`.

## Step 0 — find the plan, keep the plan folder in order

Plans live in a `plan/` folder, split by state so a human can see what is waiting, what
is running and what is finished:

```
plan/
  to-start/      written, no task started yet
  in-progress/   at least one task started
  done/          every task done
```

`plan/` sits at the git top level (or the current folder outside a repo) and is
**always gitignored** through its own `plan/.gitignore` holding `*`. The helper script
manages it:

```bash
bash "$(dirname "$0")/scripts/plan_context.sh" init      # create the folders + .gitignore (safe to re-run)
bash "$(dirname "$0")/scripts/plan_context.sh" list      # every plan, per folder, with its progress
bash "$(dirname "$0")/scripts/plan_context.sh" move <plan.md> <to-start|in-progress|done>
```

**Which plan.** You only work on plans in `in-progress/` or `to-start/` — never on one in
`done/`, unless the user names it and asks to reopen it (then move it back to
`in-progress/`).

- The user named a plan → use it.
- They did not → run `list`. If exactly one plan sits in `in-progress/` and `to-start/`
  together, use it and say which one. Otherwise show the list (in-progress first) and
  ASK. Never guess between several plans.
- The user points at a plan **outside** `plan/` (an older `<slug>-plan.md` in the repo
  root, say) → ask before moving it in; if it is tracked by git, moving it is a change
  the user has to commit, so say so.

**When to move it** (the script prints the new path — use that path from then on):

| Moment | Move |
|--------|------|
| You are about to mark the first task `[~]` and the plan is in `to-start/` | `move <plan> in-progress` |
| Close-out (Step 5) is finished and every task is `[x]` | `move <plan> done` |
| A plan in `done/` is reopened at the user's request | `move <plan> in-progress` |

Never move a plan to `done/` while any task is `[ ]`, `[~]` or `[!]`. A blocked plan
stays in `in-progress/`.

## Step 1 — check where we are

Always run this first, on a fresh session and on every resume. Never assume the plan is
untouched:

```bash
bash "$(dirname "$0")/scripts/plan_context.sh" status <plan.md>
```

It prints three things:

- **WHERE WE ARE** — every git repository under the working folder, each with its own
  branch, last commit and uncommitted files. One repo at the root is a *monorepo*;
  several repos side by side (`backend/`, `frontend/`) is a *multi-repo* folder, and
  the script says `MULTI-REPO: n repositories` when it finds one.
- **STACKS** — every project it found, each tagged with its directory, its language and
  framework, the command for its whole suite, the command for a single focused test, and
  its formatter/linter. A plan can span several stacks in either layout.
- **PLAN PROGRESS** — the checkbox tally, every task with its state, and `NEXT:`.

Two facts from that output govern everything after it:

- **`TEST_SUITE: yes`** → rules 3, 4, 6 and 7 are in force, *for the stacks that
  actually reported a test command*.
- **`TEST_SUITE: none detected`** → skip those rules entirely. Do not add a test
  framework, do not write tests, do not suggest it unless the user asks.

This is per-project, not per-repo. A folder whose Laravel `backend/` reports
`php artisan test` and whose React `frontend/` reports `(none — no "test" script)` means:
TDD every backend task, and write no tests at all for the frontend ones.

If the tally shows work already done, say so and resume from `NEXT:` — do not restart
the plan or redo finished tasks.

## Step 2 — normalize the plan (once)

If the script reports `PLAN_CHECKLIST: none`, the plan has no trackable tasks yet.
Before writing any code, rewrite the plan file so that:

1. Every concrete step becomes a checkbox task: `- [ ] <task>`. Keep the plan's own
   headings, ordering and wording — you are adding checkboxes, not rewriting the plan.
   Split a step into several tasks only when it plainly covers separable units of work.
2. **Every task names the project it belongs to** whenever the plan covers more than one
   (`- [ ] backend: add POST /orders`, `- [ ] frontend: order form`). Use the directory
   names from **STACKS**. If the plan already separates the work under headings like
   "Backend" / "Frontend", the heading supplies the tag — keep the structure and tag the
   tasks anyway, so a task read on its own is never ambiguous about where it lands.
3. A **Ground rules** block is inserted at the top (copy the rules from Step 3 below),
   so the contract travels with the file.
4. A **Deviations** section is appended at the bottom, empty, for rule 5.

Show the user the normalized plan and get a go-ahead before implementing. If the plan
already has checkboxes, skip this step — it is already normalized.

## Step 3 — the ground rules

These bind every task. They are also what gets written into the plan file in Step 2.

1. **Check state first, then continue.** Re-run Step 1 at the start of every session.
   Resume from the first unchecked task; never redo checked ones.
2. **Tick tasks off as they land.** Mark a task `[~]` when you start it, and `[x]` the
   moment its code is written, its tests pass and it is genuinely done. One task at a
   time — never batch-check several tasks after the fact, and never check a task you have
   not finished. The states are `[ ]` todo, `[~]` in progress, `[x]` done, `[!]` blocked;
   the script counts everything that is not `[x]` as remaining and resumes on the first
   of them. If the plan spells the state out in words too (`— DOING —`, written by the
   `plan-write` skill), change the word and the bracket together so they never disagree.
3. **TDD.** *(projects with tests)* For each task: write the failing test first, watch it
   fail for the right reason, then write the minimum code to make it pass, then refactor.
   A test that passes before the feature exists is testing nothing.
4. **Every feature ships with a test.** *(projects with tests)* If a task touches behavior
   that has no test, add one. Cover the behavior the plan asked for, plus the error path
   it implies — not every branch of every helper.
5. **Build only what the plan says.** No invented scope, no drive-by refactors, no extra
   endpoints/flags/abstractions "while we're here". The one exception: if the plan omits
   something without which the planned feature is broken or unshippable, add the minimum
   to make it work, then log it under **Deviations** in the plan file (what you added,
   and why the plan breaks without it). If the gap is a judgment call rather than an
   outright break, stop and ask instead.
6. **Tests must pass before a task is checked off.** *(projects with tests)* Run the tests
   covering the task you just did, from that project's directory, with that project's
   focused command. All green, then tick the box. If they fail, fix the code — never
   weaken the test: no deleted assertions, no `skip`/`xfail`/`markTestSkipped`, no
   loosened matchers to force green.
7. **Run each touched project's full suite before reporting the plan complete.**
   *(projects with tests)* Per-task runs catch the task; only the full suite catches what
   the task broke elsewhere. If the plan touched backend and frontend, run both. Report
   the results honestly — if any is red, say so and show the failure.
8. **Right project, right repo.** A task belongs to exactly one project. Run its tests,
   its formatter and its linter *in that project's directory* — a green backend suite
   says nothing about a frontend task. In a multi-repo folder each repo has its own
   branch, its own history and its own working tree: check the branch you are on in
   **that** repo before editing it, and never assume one branch spans both.
9. **Cross-repo changes land producer-first.** When a frontend task consumes a backend
   endpoint, field or type the plan has not built yet, do the backend task first if the
   plan allows it. If the plan's order forces the reverse, say so and ask before
   inventing a contract the backend does not serve — a UI written against a guessed
   payload is a bug the tests cannot see.
10. **Don't commit, push, or open a PR unless asked.** Leave the work in the tree, in
    every repo. Never force-push, rebase, or amend on your own initiative.
11. **Match the codebase.** Follow the conventions, naming and structure already there,
    per project — the backend's idioms are not the frontend's. Run that project's
    formatter/linter if it has one (the **STACKS** output names it).
12. **Ambiguity stops work.** When the plan is unclear, self-contradictory, or collides
    with what the code actually does, ask. Do not guess and build.
13. **Run the whole plan without stopping.** Once you start, go from task to task until
    every task is `[x]` — do not pause between tasks or phases, and never ask "shall I
    continue?". Stop only when:
    - **the user asked you to** — to stop, or to do only some tasks or one phase;
    - **you need a human** — an ambiguity (rule 12), an Open question, a judgment-call
      gap (rule 5), a contract the backend does not serve yet (rule 9), a credential, a
      login or another manual step, or an action that needs the user's OK first;
    - **you are stuck** — a `[!]` BLOCKED task whose blocker is not done, a `verify:`
      that still fails after real attempts to fix the code, or a broken environment
      (missing tool, service down) you cannot fix inside the plan's scope.
    When you stop, leave the task `[~]` (or `[!]` with a `blocked-by:` line), keep the
    plan in `plan/in-progress/`, and say exactly what you need to go on.

## Step 4 — implement, task by task

Repeat until no unchecked tasks remain. If the plan is still in `plan/to-start/`, move
it to `plan/in-progress/` before you mark its first task `[~]` (Step 0). For each task,
in this order:

1. **Read the task** and the surrounding plan context. Identify its project from the tag
   (rule 8) and read the code it touches before writing anything.
2. **Write the failing test** (rules 3, 4 — only if that project has tests). Run it from
   that project's directory; confirm it fails for the intended reason.
3. **Write the minimum code** to satisfy the task as written (rule 5).
4. **Run the task's tests** (rules 6, 8 — only if that project has tests). Green, or fix
   the code and rerun.
5. **Tick the box** in the plan file (rule 2), and add any **Deviations** entry the task
   required (rule 5).
6. **Report the task** in one or two lines: what landed, in which project, which tests
   cover it. Then go straight on to the next task (rule 13) — no waiting for a reply.

Each task is one full loop — one task, one loop, one tick — and the loops run back to
back. Never start the next task before the current one is ticked, and never stop
between tasks unless rule 13 says so.

## Step 5 — close out

When every box is checked:

1. Run the full test suite of **every project the plan touched** (rule 7) and report the
   real results, per project.
2. Run each touched project's formatter/linter (rule 11).
3. Summarize: tasks completed per project, tests added, and every **Deviations** entry,
   so the user sees exactly where the implementation departed from the plan and why.
4. Leave committing to the user (rule 10). In a multi-repo folder, tell them which repos
   have uncommitted work, so nothing is left behind in the one they are not looking at.
5. Move the plan to `plan/done/` (Step 0) and tell the user its new path. Only when every
   task is `[x]` — a plan with any task left stays in `plan/in-progress/`.

If a task could not be completed, leave its box unchecked, leave the plan in
`plan/in-progress/`, and say which task and why. An unchecked box is information; a
checked box on unfinished work is a lie the next session will trust.
