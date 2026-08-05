---
name: plan-write
description: Write an implementation plan as a markdown file for ANOTHER AI agent to execute — not for a human to read. Surveys the repo(s) first, interrogates the user until nothing is ambiguous, then emits a `<slug>-plan.md` of phases and sub-phases whose tasks each carry an explicit state ([ ] TODO / [~] DOING / [x] DONE / [!] BLOCKED), exact file paths, exact commands, and a done-when condition, so a small or weak model can tell instantly where it left off and what to do next. Decides the test policy per project: a project with a test suite is planned test-first with full test coverage of every behavior and edge case a task names; a project without one gets no tests, no test framework, and no suggestion of either. Output is consumed by the plan-execute skill. Use when the user says e.g. "write a plan for X", "create a planning file", "plan out this feature", "make a spec for another agent to build".
---

# plan-write

Produce a plan file that a **weaker AI agent** will execute alone, without you, and
without the conversation you are having now. That reader cannot infer, cannot ask you
follow-ups mid-task, and will do literally what the file says. Everything it needs must
be on the page.

The output is consumed by the `plan-execute` skill, so the task format must stay exactly
as the template defines it.

Paths below are relative to this skill folder, so the skill works wherever installed.

## Step 1 — survey the code before writing anything

Never write a plan from the user's description alone. A task naming a file that does not
exist is a task the executing agent cannot recover from.

```bash
bash "$(dirname "$0")/../plan-execute/scripts/plan_context.sh" stacks
```

This prints every git repository (one repo = monorepo, several = a multi-repo folder,
each with its own branch), and every project found, with its language, framework, test
commands and linter. If the script is not present, survey by hand: find the manifests
(`composer.json`, `package.json`, `pyproject.toml`, `go.mod`), the test config, and the
CI workflow.

Then read the code the plan will touch: the existing controllers/components/models near
the feature, the naming conventions, an existing test to copy the shape of. You are
looking for the real paths, real class names, and real commands to write into the tasks.

## Step 2 — interrogate the user

Ask questions before writing. Doubt is the failure mode: an ambiguity you leave in the
plan becomes an invention by an agent too weak to notice it is guessing. Ask generously —
the user asked for this. Batch related questions rather than dribbling them out.

Ask about anything you cannot answer from the code, and always about these:

1. **Goal** — what must be true when the work is finished?
2. **Scope boundaries** — what is explicitly NOT part of this? (Becomes *Out of scope*.)
3. **Which projects** — backend only, frontend only, or both? Which repo does each part
   land in?
4. **Contracts** — for an API: exact route, method, request payload, response shape,
   status codes. For a UI: what it renders, what it calls.
5. **Data** — new tables/columns/fields, migrations, nullable or required, defaults.
6. **Auth and permissions** — who may call this, what happens when they may not.
7. **Edge cases and errors** — empty results, validation failures, duplicates, what the
   user sees on failure.
8. **Acceptance** — how does the user (not the agent) confirm this works?
9. **Ordering constraints** — anything that must land before something else.
10. **Reuse** — is there existing code the agent should extend rather than duplicate?

If the user says to stop asking and just write it, do that — but put every unresolved
item under **Open questions** in the file, and tell the user that the executing agent is
instructed to stop and ask when it reaches one.

## Step 3 — write the file

Copy `templates/PLAN_TEMPLATE.md` from this skill folder and fill it in. Keep its
structure, its headings and its task format exactly — `plan-execute` parses the
checkboxes, and the executing agent relies on the `READ THIS FIRST` block.

**Filename:** `<slug>-plan.md` in the current folder, where `<slug>` is a short kebab-case
name for the work (`orders-api-plan.md`, `user-auth-plan.md`). Use a different path only
if the user names one. If the file already exists, show the user and ask before
overwriting — never clobber a plan that may be half-executed.

**Fill in the Projects table** from Step 1's output, with the real commands. This table
is what switches the test rules on and off for the executing agent, so get it right —
see the test policy below.

## Step 3b — the test policy (per project, never per repo)

Step 1 tells you, for each project, whether it has a test suite. That fact is binding,
and it is decided per project: in one plan the Laravel `backend/` can be under full TDD
while the `frontend/` gets no tests at all.

**Project HAS tests** (the survey printed a test command):

- Embrace it. The plan drives the work test-first.
- Every task that adds or changes behavior gets tests — the behavior asked for, plus
  every error case and edge case the task names. Do not ration them; if a task implies
  four cases, the plan says to test four cases.
- Write the test-first sequence into the task's `do:` steps, in this order: write the
  failing test, run it, watch it fail, write the code, watch it pass.
- The task's `verify:` is that project's focused test command, naming the real test file
  or filter.
- Where the survey found no test for existing code the task touches, add a task to cover
  it — that is not invented scope, it is rule 5 of the file.

**Project has NO tests** (the survey printed `none`):

- Write `none` in both of its test columns. That is the switch.
- Write no test tasks. Name no test file. Do not add a test framework, a runner, a
  config, or a single spec. Do not put "consider adding tests" in the plan, not even as
  a suggestion or an Open question.
- Its tasks still need a `verify:` — the executing agent cannot mark a task DONE without
  running something. Use, in order of preference: the project's type-check
  (`npx tsc --noEmit`), its build (`npm run build`), its linter, or a precise observable
  fact the agent can check by hand (`curl -i localhost:8000/api/orders` returns `201`).
  Never leave `verify:` empty, and never fill it with a test command.

If the user wants a project's missing test setup added, that is a separate plan. Say so;
do not smuggle it into this one.

## Step 4 — how to write the tasks

The reader is a small model. Write for it.

**One task = one verifiable change.** If a task cannot be proved done by a single
command or a single observable fact, split it. Prefer five small tasks over one large
one. A task that takes more than a few file edits is too big.

**Every task carries, without exception:**

- an ID (`T2.3`) and a state (`[ ] TODO`),
- the project name, when the plan spans more than one project,
- `files:` — exact paths, relative to the project directory,
- `do:` — numbered, imperative steps,
- `done-when:` — the observable fact that proves it works,
- `verify:` — the exact command to run, including the `cd` into the project directory.

Add `depends-on: T1.2` whenever order matters. For projects that have tests, the task
that adds behavior is where the test gets written first, and `verify:` names the test
command that must go from red to green. For projects with `none`, `verify:` is a build,
a type-check, a lint, or a stated observable fact — never a test command.

**Language rules for a weak reader:**

- Use imperative verbs: *Add*, *Create*, *Rename*, *Delete*. Not "we should consider".
- Name the same thing the same way every time. Never a synonym. If it is
  `OrderController`, it is never "the orders controller" in the next task.
- No pronouns pointing at earlier tasks ("it", "that file"). Repeat the name.
- No words that assume judgment: "appropriate", "properly", "as needed", "etc.",
  "obviously", "handle the edge cases". Say the exact thing to do.
- Give exact values: route strings, status codes, column types, field names.
- A short code block is good when it fixes a contract (a payload shape, a function
  signature). Do not write the implementation for the agent — that is its job.

**Phases** group tasks that share a goal. Each phase gets a one-sentence `Goal:` and a
`Depends on:`. Split into sub-phases (`### Phase 2.1`) only when a phase grows past
roughly six tasks. Order phases so nothing is consumed before it exists: in a backend +
frontend plan, the endpoint is built before the UI that calls it.

**Cross-project tasks belong to exactly one project.** "Add POST /orders" is a backend
task. "Call POST /orders from the order form" is a frontend task. Never one task that
edits both.

## Step 5 — check the file before handing it over

Re-read the finished file as if you were the weak agent, and confirm:

- Every task has `files:`, `do:`, `done-when:`, `verify:`.
- Every path named actually exists, or is explicitly created by an earlier task.
- Every dependency points at a task that appears earlier in the file.

**The test policy is a hard gate, not a preference.** Scan every task against its
project's row in the Projects table and fix any violation before handing the file over:

- A project with `none` in its test columns has **zero** tasks that write a test, name a
  test file, install a runner, or mention testing — and **zero** `verify:` commands that
  run tests. If you wrote one, delete it.
- A project with a test command has **no** behavior-changing task without tests, and
  every such task's `do:` puts the failing test before the code, with `verify:` pointing
  at that project's focused test command.
- No `verify:` line is empty.
- The `Progress:` line reads `0/<N>` and `<N>` is the real number of tasks.
- Nothing in *Out of scope* is quietly built by a task.
- No task says "and", "also", or "then" joining two separable changes.

Then run the plan through the executing skill's own reader to prove it parses:

```bash
bash "$(dirname "$0")/../plan-execute/scripts/plan_context.sh" status <slug>-plan.md
```

It must report the right task count and `NEXT:` must point at the first task. If it
reports `PLAN_CHECKLIST: none`, the checkbox format is broken — fix it.

Finally, tell the user: the file path, the phase names, the task count, and every entry
left under **Open questions**. Say that the plan is executed with the `plan-execute`
skill, and that you have not written any code.
