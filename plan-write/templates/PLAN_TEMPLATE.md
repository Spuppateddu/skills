# <TITLE> — implementation plan

<!-- Written by the plan-write skill. Executed by an AI agent, not a human. -->

## READ THIS FIRST

You are an AI agent. This file is your instructions. Read this whole file before you
write any code. Do exactly what this file says. Do not do anything this file does not say.

### Task states

Every task has ONE state. The bracket and the word always mean the same thing:

| Bracket | Word    | Meaning |
|---------|---------|---------|
| `[ ]`   | TODO    | Not started. |
| `[~]`   | DOING   | Started, not finished. |
| `[x]`   | DONE    | Finished, and its `verify:` command passed. |
| `[!]`   | BLOCKED | Cannot continue. A `blocked-by:` line says why. |

### Where do I start?

1. Read the `Progress:` line below.
2. Read the task list from the top. Find the FIRST task that is not `[x]` DONE.
3. If that task is `[~]` DOING, a previous agent stopped in the middle of it. Read the
   task. Look at the files it names. Work out what already exists. Continue from there.
4. If that task is `[!]` BLOCKED, read its `blocked-by:` line. If the blocker is now
   DONE, change the task back to `[ ]` TODO and start it. If the blocker is not DONE,
   stop and tell the user.
5. That one task is your work. Do that task only. Do not start the next task.

### How do I update this file?

- Before you start a task: change `[ ]` to `[~]`, and change `TODO` to `DOING`. Save the file.
- After the task's `verify:` command passes: change `[~]` to `[x]`, and change `DOING`
  to `DONE`. Save the file. Then update the `Progress:` line.
- Change the bracket AND the word every time. They must never disagree.
- Never delete a task. Never reorder tasks. Never add a task.
- Never write `[x]` DONE unless you ran the task's `verify:` command and it passed.
- If you cannot finish a task, leave it `[~]` DOING and tell the user what stopped you.
  A wrong `[x]` makes the next agent skip unfinished work.

Progress: 0/<N> tasks done

---

## Rules you must follow

1. Do only what a task says. Do not add features, endpoints, options, or abstractions
   that no task asks for. Do not refactor code that no task mentions.
2. Do one task at a time. Finish it, verify it, mark it DONE, then stop and report.
3. Look at the Projects table. Find the row for the project this task belongs to.
   - If its test columns show commands, that project **has tests**. Follow rules 4 and 5.
   - If its test columns say `none`, that project **has no tests**. Do NOT write tests for
     it. Do NOT install a test framework. Do NOT suggest adding tests. Skip rules 4 and 5.
4. **(projects that have tests)** Write the test FIRST. Run it. Watch it fail. Then write
   the code until the test passes. A test that passes before you write the code tests
   nothing and must be rewritten.
5. **(projects that have tests)** Every task that changes behavior ships with tests: the
   behavior the task asks for, AND each error case and edge case the task names. If a
   behavior the task adds has no test, the task is not DONE.
6. Run the task's `verify:` command before you mark the task DONE. It must pass.
7. Never make a test pass by weakening it. Do not delete assertions. Do not use `skip`,
   `xfail`, or `markTestSkipped`. Fix the code instead.
8. Run each command in the directory given in the Projects table. A passing backend test
   does not prove a frontend task works.
9. Do not run `git commit`, `git push`, or open a pull request unless the user asks you to.
10. Write code in the same style as the code already in that project.
11. If a task is unclear, or the code does not match what the task says, STOP. Ask the
    user. Do not guess.
12. If a task cannot work as written because the plan is missing something, add the
    smallest thing needed to make it work, and write what you added and why under
    **Deviations** at the bottom of this file.

---

## Projects

<!-- One row per project. Commands come from `plan_context.sh stacks`. -->

| Name | Directory | Language / framework | Run one test | Run all tests | Lint / format |
|------|-----------|----------------------|--------------|---------------|---------------|
| backend | `backend/` | PHP / Laravel | `cd backend && php artisan test --filter=<TestName>` | `cd backend && php artisan test` | `cd backend && vendor/bin/pint` |
| frontend | `frontend/` | TS / Next | `cd frontend && npx vitest run <file>` | `cd frontend && npm test` | `cd frontend && npx eslint .` |

<!-- A project with no test suite gets the literal word `none` in BOTH test columns.
     `none` means: rules 4 and 5 are off for that project's tasks. Never write a test
     for it, never install a test framework, never suggest one. Its tasks are verified
     with a build, a type-check, a lint, or a stated observable fact instead. -->

**This table decides the test rules. Read the row for the project of the task you are
doing. Test columns with commands mean write tests first. Test columns saying `none`
mean write no tests at all.**

## Goal

<One paragraph. What must be true when every task is DONE. Written so an agent can
check it.>

## Out of scope

<Bullet list of things a reader might assume are included, but which are NOT. Be
explicit — this list is what stops the agent inventing work.>

- <thing not to build>

---

## Phase 1 — <name>

Goal: <one sentence>
Depends on: nothing

- [ ] T1.1 — TODO — <project>: <one imperative action>
      files: `<exact/path/one.php>`, `<exact/path/two.php>`
      do:
        1. <exact step>
        2. <exact step>
      done-when: <the observable fact that proves it works>
      verify: `cd <project-dir> && <exact command>`

- [ ] T1.2 — TODO — <project>: <one imperative action>
      files: `<exact/path>`
      depends-on: T1.1
      do:
        1. <exact step>
      done-when: <observable fact>
      verify: `cd <project-dir> && <exact command>`

## Phase 2 — <name>

Goal: <one sentence>
Depends on: Phase 1

### Phase 2.1 — <sub-phase name, only if this phase is large>

- [ ] T2.1 — TODO — <project>: <one imperative action>
      files: `<exact/path>`
      do:
        1. <exact step>
      done-when: <observable fact>
      verify: `cd <project-dir> && <exact command>`

---

## Final checks

Do these only when every task above is `[x]` DONE.

- [ ] F.1 — TODO — Run the full test suite of every project whose test columns are not
      `none`. All must pass. Skip any project whose test columns say `none`.
      verify: `cd backend && php artisan test` and `cd frontend && npm test`
- [ ] F.2 — TODO — Run the lint/format command of every project you changed.
- [ ] F.3 — TODO — Report to the user: tasks done, tests added, every Deviations entry,
      and which repositories still have uncommitted changes.

---

## Open questions

<Anything the plan author could not resolve. If you hit one of these while working,
STOP and ask the user. Delete a line here only when the user has answered it.>

- <question, or "none">

## Deviations

<Write here every time you do something the plan did not ask for, as allowed by rule 11.
One line each: what you added, and why the task could not work without it. If empty,
leave "none".>

- none
