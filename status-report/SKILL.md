---
name: status-report
description: Give a short status report on the work in progress — which task is running now, how far it has got, the percentage done, how many tasks are left, what is blocked, and how much time is left when it can be measured (from the pace of the tasks already done, or from the tracker's estimated vs spent hours), and says "not measurable" instead of guessing when it can't. Reads the source that fits — a plan-write / plan-execute plan file (plan/in-progress/…), a Redmine ticket and its subtasks, or the work done in the current chat — and changes nothing. Use when the user invokes /status-report or asks e.g. "where are we", "status report", "how much is left", "what percentage is done", "how long until it's finished", "a che punto siamo", "quanto manca".
---

# status-report

Tell the user, in one short screen, **where the work stands**: what is running now,
how much is done, how much is left and, when the data allows it, how long it will
take.

This skill only reads. It never ticks a task, moves a plan, updates a ticket or
logs time.

Paths below are relative to this skill folder. The helper script needs `bash`,
`awk` and `jq`.

## Step 1 — pick the source

Use the first one that applies, and say in the report which one you used:

1. **The user named it** — a plan file, a Redmine ticket (`#1234`), a version or
   milestone. Use that.
2. **A plan file** — the plan this chat is working on (plan-execute ran here, or
   the user pointed at it earlier). If there is none in the chat, look for plans:
   `plan/in-progress/*.md` at the git top level, or the `list` mode of the
   plan-execute helper if it is installed next to this skill
   (`../plan-execute/scripts/plan_context.sh list`). Exactly one plan in
   `in-progress/` → use it. Several → show them and ask which one. Never guess.
3. **The current chat** — no plan and no ticket: report on the work done in this
   conversation. Use the agent's own task list if it has one (a todo / task tool);
   otherwise build the list from what the user asked and what has been done so far.

If a plan and a ticket both cover the same work (the plan names the ticket), report
on the plan and add the ticket's hours as a second view of the time.

## Step 2 — collect the numbers

### From a plan file

```bash
bash "$(dirname "$0")/scripts/plan_progress.sh" <plan.md>
```

It prints:

- **COUNTS** — tasks per state (`[x]` done, `[~]` doing, `[ ]` todo, `[!]`
  blocked), how many are left and the percentage done. "Left" means every task
  that is not `[x]`, final checks included.
- **PHASES** — the same count for each `## Phase` heading.
- **CURRENT** — the `[~]` task, or the next `[ ]` task when nothing is running.
- **BLOCKED** — every `[!]` task.
- **TIMING** — read from the Claude Code session logs (`~/.claude/projects/*/*.jsonl`;
  set `CLAUDE_PROJECTS_DIR` to look elsewhere). Every edit of the plan that turned a
  task into `[x]` is a "done" moment with a timestamp. From those it gives the
  wall-clock span, the active time (gaps over 30 minutes are breaks and don't
  count), the pace (the median time between two tasks done, leaving out gaps
  over 2 hours) and an **ETA** = pace × tasks left, with a range.

The ETA is only printed with at least 3 tasks done in the logs. Fewer than that, or
a plan run on another machine or by another agent → the script says "not measurable".

Also read the `[~]` task in the plan itself: its `blocked-by:` lines, and any notes
written under it, tell you what it is doing right now.

### From a Redmine ticket

Use the Redmine MCP tools (read-only ones only):

- `get_redmine_issue` — status, `done_ratio` (the % the team set by hand),
  `estimated_hours`, `spent_hours`, due date, assignee.
- `list_subtasks` — the subtasks with their status: that is the task list. Count
  closed vs open ones.
- `list_time_entries` for the ticket, if `spent_hours` is missing.

Percentage: if the ticket has subtasks, use closed ÷ total and show the ticket's own
`done_ratio` next to it when the two differ. No subtasks → use `done_ratio`.

Time left: `estimated_hours − spent_hours`, when both are set. If spent is already
over the estimate, say so plainly ("over by 3h") instead of showing a negative
number. Due date in the past → say it is late.

Another tracker (GitHub issues, Jira…) works the same way: the task list is the
sub-issues or checklist, the hours are whatever the tracker records.

### From the current chat

- Tasks: the agent's task list, or the steps the user asked for. Number them.
- Done / doing / left / blocked: from what has really happened in the chat — a
  task is done only if it was finished and checked (tests passed, the command
  worked), not just started.
- Time: how long this session has run so far is measurable (first and last
  message times in this session's `.jsonl` log). Time left is usually **not**
  measurable here — say so, unless at least 3 similar tasks are done and the
  pace is clear.

## Step 3 — write the report

Keep it short. Use this shape:

```
## Status — <plan file name / ticket #id title / "this chat">

**Now:** <current task id + one line on what it does>  (<doing / next / blocked>)
**Blocked:** <task id — why>   (only if something is blocked or waits on the user)

**Progress:** ▓▓▓▓▓▓▓░░░ 73% — 34 of 46 tasks done
**Left:** 12 tasks (1 doing, 11 to do, 0 blocked)
**Time left:** about 3h40m of active work (range 2h50m – 5h10m), from a pace of
18m per task over the last 34 tasks
  — or —
**Time left:** not measurable — <the reason, in one line>

| Phase | Done | % |
|-------|------|---|
| …     | 5/7  | 71% |

**Source:** <what you read: the plan path, the ticket, the session logs>
```

Rules for the report:

- **The progress bar** has 10 cells: one `▓` for every full 10%, `░` for the rest.
- **Phase table** only when the source has phases or subtasks, and only when there
  are more than two of them. A finished phase can be folded into one line
  ("Phases 0–5: all done").
- **Never invent a time.** An ETA comes from measured data (log timestamps or the
  tracker's hours) and the report says which. No data → "not measurable" and why.
  Don't turn a gut feeling into a number.
- **Say what the ETA can't see**: it is the active working time at the pace so far.
  If the tasks left are clearly heavier than the ones done (a "run the full
  benchmark" task, a deploy that waits on a human), say so in one line.
- **Blocked work first.** If a task is `[!]` or waiting on the user, put that line
  right after **Now** — that is the thing the user has to act on.
- Plain words, short lines. The report is a reply in the chat, not a file: don't
  save it anywhere unless the user asks.
- Any end-of-reply status line the user's own rules ask for still goes at the end.
