---
name: api-branch-diff
description: Compare an HTTP API's response across two git branches to confirm a change is transparent (a refactor, a field removal, a serializer migration didn't alter the payload). Tech-agnostic — works for any backend that serves the endpoint over HTTP. Use when the user says e.g. "compare the users API between branch-x and main", "diff the orders endpoint across these two branches", "make sure my refactor didn't change the response".
---

# API branch-diff

Fire the relevant API endpoint(s) on one branch, snapshot the response payload,
switch to the other branch, recall the same endpoint(s), and diff. If the payloads
differ, the change is NOT transparent — surface the diff as the problem.

The user chooses BOTH branches to compare. Never assume them: if the user did not
name both branches, ASK which two before doing anything else.

Responses are fetched with `curl` against a running server, so the app must be
reachable at a base URL. Snapshots go to a gitignored `DUMP_DIR` (default
`./.api-branch-diff/`). Paths below are relative to this skill folder, so the skill
works wherever it is installed.

## Setup — ask the user these first

Collect every input before touching git. Ask for anything not already given:

1. **Branch A and Branch B** — the two branches to compare. Never assume them or
   default to `main`/the current branch.
2. **Base URL** of the running server (e.g. `http://localhost:8000`).
3. **Endpoint(s) to test** — the GET path(s). If the user is unsure, hit the API's
   index/list route to discover detail URLs. Prefer covering BOTH a list and a detail
   endpoint, since they often serialize via different code paths.
4. **Record IDs** for any detail routes — real, data-rich records whose detail route
   returns 200 (not 404). Get them from the user or a list endpoint.
5. *(optional)* **Volatile fields** to ignore in the diff, if the defaults
   (timestamps, durations, echoed request params) miss something app-specific.

Then confirm each chosen URL returns 200 before comparing — a 404 on both branches
proves nothing.

## Steps

1. **Write the endpoints file** to `$DUMP_DIR/endpoints.json` as a JSON object of
   `{ "short_name": "/path/..." }` (paths only — the base URL is supplied separately).
   Record the branch you start on so you can return to it at the end.

2. **Snapshot both branches.** Switch branches around a clean tree, auto-stashing the
   user's uncommitted work — never make a commit on their behalf:

   1. `git stash push` — tracked changes only. Do **NOT** use `-u`: the gitignored
      snapshots in `DUMP_DIR` must survive the switches. Capture whether anything was
      stashed ("No local changes to save" → nothing to pop later).
   2. Record the starting branch.
   3. For EACH branch: `git checkout <branch>` → restart/reload the server so it serves
      the checked-out code → run the dump (see **Running** below) with
      `BRANCH_TAG=<branch>`.
   4. `git checkout <starting-branch>`.
   5. `git stash pop` — only if step 1 actually stashed something.

   **Guaranteed cleanup:** if any step fails, still return to the starting branch and
   pop the stash before reporting the error — never leave the user on the wrong branch
   with their work buried. If the pop conflicts, surface it; do not swallow it.

3. **Diff and report.** For each endpoint (any `/` in a branch name becomes `-` in the
   filename, e.g. `feature/x` → `feature-x`):
   `diff $DUMP_DIR/<name>.<branchA>.json $DUMP_DIR/<name>.<branchB>.json`.
   - Identical → report ✅, the change is transparent.
   - Differs → report ❌ with the diff. Then judge whether the difference is the
     expected effect of the change or an unintended regression.

## Running the dump

Requires the app running and reachable at `BASE_URL`, plus `jq`.

```bash
D=./.api-branch-diff
BASE_URL=http://localhost:8000 \
ENDPOINTS_FILE=$D/endpoints.json BRANCH_TAG=<tag> DUMP_DIR=$D \
  bash "$(dirname "$0")/scripts/dump_api.sh"
```

The server must be restarted (or run a code-reloading dev server) after each
`git checkout` so it serves the checked-out branch's code.

## Notes

- If the response has a top-level `data` envelope, only that is compared; otherwise the
  full body is compared with volatile `meta` keys removed, so identical payloads diff
  clean. The dropped keys default to common volatile fields (timestamps, durations,
  echoed request params) and can be overridden with the `VOLATILE` env var
  (comma-separated).
- The script lives in this skill folder and is committed; the `.<tag>.json` snapshots
  in `DUMP_DIR` are gitignored — add `.api-branch-diff/` to the project's `.gitignore`
  if it isn't already.
