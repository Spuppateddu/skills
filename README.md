# skills

A cross-agent collection of [Agent Skills](https://agentskills.io). Each skill is a
folder with a `SKILL.md` — an open standard read natively by Claude Code, Codex,
Cursor, opencode and ~40 other agents. A skill is a reusable prompt that the model
loads *on demand* when its `description` matches the task, optionally bundling scripts
it can run.

## Skills

| Skill | What it does |
|-------|--------------|
| [`api-branch-diff`](./api-branch-diff/) | Compare an HTTP API's response across two git branches to prove a refactor didn't change the payload. Tech-agnostic — curl against any running backend. |
| [`branch-review`](./branch-review/) | Code-review a git diff (uncommitted/unpushed work, or two branches you pick) for security, type safety, duplication, missing tests, and speed — it times or counts what the diff makes hot instead of only eyeballing it. Tech-agnostic; findings graded MEDIUM→CRITICAL (no nits), each self-contained (where / what / what it causes / how to fix) so you can paste one straight to a fixing agent. Keeps a per-branch ledger in `.git/` so a re-review converges instead of looping on the same findings. |
| [`branch-review-task-fix`](./branch-review-task-fix/) | Take **one** finding from a review and decide whether it's real or a hallucination — reads the code around the line, checks the claimed mechanism actually exists, re-grades the severity, explains in plain language what breaks and when, and proposes a concrete fix. Pairs with `branch-review`. |
| [`plan-write`](./plan-write/) | Write an implementation plan as markdown for **another AI agent** to execute. Surveys the repos, interrogates you until nothing is ambiguous, then emits phases of tasks with explicit states, exact paths and exact verify commands. Pairs with `plan-execute`. |
| [`plan-execute`](./plan-execute/) | Implement a markdown plan under ground rules: normalize it into a tracked checklist, build it task by task in TDD order, tick each task off in the file, run that project's tests. Strictly no invented scope. Detects PHP, Python, JS/TS, Go, Rust, Ruby across monorepos and multi-repo folders (`backend/` + `frontend/`). |
| [`gdr-new-game`](./gdr-new-game/) | Add a new tabletop RPG system to the **gdr-companion** app from its character sheet (PDF or image) plus, when there is one, its rulebook PDF. Project-manager half of the job: reads the sheet, maps every box onto a panel the app already has (relabelling a tab instead of building one), keeps rules text out of the repo — names and labels are seeded, descriptions stay empty free text the player types — and seeds the game idempotently so a fresh server gets every game. Emits a plan that [`plan-execute`](./plan-execute/) then builds. Specific to one project, kept here so it travels with the rest. |
| [`pdf-doc`](./pdf-doc/) | Write a document — report, proposal, offer, manual, spec — as a **self-contained** styled HTML file and render it to PDF. One fixed layout (cover, auto-built table of contents, consistent tables/callouts/code) so a whole set of PDFs matches; you supply one or two brand colours, an optional logo, the language and the verbal style. The HTML stays editable: change it and re-run the converter — the TOC rebuilds itself. Installs nothing, renders through the Chrome already on the machine. |
| [`summarize-transcript`](./summarize-transcript/) | Summarize a transcript — meeting, work call, interview, lesson, RPG session — or any text file with a **fully local** LLM (llama.cpp), so nothing is uploaded. Auto-chunks long inputs; writes the summary in the input's own language. Pairs with [call-transcriber](https://github.com/Spuppateddu/call-transcriber). |

Alongside them, [`global-rules.md`](./global-rules.md) holds the always-on rules that
are *not* a skill — see [Global rules](#global-rules) below.

**Supported OS:** Linux and macOS. Requirements: `bash`, `git`, `curl`, `jq`
(`apt install jq` / `brew install jq`). The scripts avoid bash 4+ features, so
macOS's default bash 3.2 works. `pdf-doc` renders through a Chrome/Chromium you
almost certainly already have (WeasyPrint or wkhtmltopdf also work if you prefer).
`summarize-transcript` additionally needs a local
[llama.cpp](https://github.com/ggml-org/llama.cpp) build and a GGUF model (paths are
configurable — see its SKILL.md).

## Setup

The same repo drives every agent. Install once with the universal loader, or wire each
tool manually below.

### Universal installer (recommended)

[`openskills`](https://github.com/numman-ali/openskills) copies the skills into the
right place for whatever agent you use and generates the `AGENTS.md` glue that
non-Claude tools read:

```bash
# project-local, multi-agent (writes ./.agent/skills + ./AGENTS.md)
npx openskills install Spuppateddu/skills --universal

# or Claude-only, project-local (writes ./.claude/skills)
npx openskills install Spuppateddu/skills

# global for the current user
npx openskills install Spuppateddu/skills --universal --global

npx openskills sync   # pull updates later
```

### Per-agent manual setup

If you'd rather not use the installer, point each agent at one clone so there's a
single source of truth (no per-tool copies that drift):

```bash
git clone git@github.com:Spuppateddu/skills.git ~/code/skills
```

**Claude Code** — reads `~/.claude/skills/` (all projects) or `<project>/.claude/skills/`.
Symlink the clone so edits are live:

```bash
ln -s ~/code/skills ~/.claude/skills
```

Skills auto-activate by `description`; no further config. (`/plugin` marketplace
install is an alternative but needs a nested plugin layout — this repo uses the flat
layout for symlink + openskills simplicity.)

**Codex CLI** — discovers skills via `AGENTS.md`. Run the universal installer above to
generate it, or add a clone reference to your project/global `AGENTS.md` (`~/.codex/`
for global). Codex then loads a skill when the task matches its description.

**Cursor** — reads `AGENTS.md` natively. The universal install's `AGENTS.md` makes the
skills discoverable; alternatively mirror a skill's instructions into
`.cursor/rules/`. Restart Cursor after adding it.

**opencode** — reads the `SKILL.md` standard and `AGENTS.md`. Either run the universal
installer, or symlink the clone into opencode's skills directory
(`~/.config/opencode/` global, or the project root's `AGENTS.md`).

> Rule of thumb: keep **one** clone, and let every agent reference it (symlink or
> `AGENTS.md`). Use `openskills sync` / `git pull` to update all of them at once.

## Global rules

[`global-rules.md`](./global-rules.md) is the opposite of a skill: a skill is loaded
*on demand* when its `description` matches the task, while these rules must be in
context in **every** session of **every** project. Each agent has a different file for
that, so this one is wired in separately from the skills above.

The paths below are **identical on Linux and macOS** (all three agents use `$HOME`,
not `~/Library` or `%APPDATA%`).

| Agent | Global instructions file |
|-------|--------------------------|
| Claude Code | `~/.claude/CLAUDE.md` |
| Codex CLI | `~/.codex/AGENTS.md` |
| opencode | `~/.config/opencode/AGENTS.md` |

Assuming the clone is at `~/code/skills`:

**Claude Code** — `CLAUDE.md` supports `@`-imports, so reference the file instead of
copying it and a `git pull` updates the rules everywhere:

```bash
mkdir -p ~/.claude
echo '@~/code/skills/global-rules.md' >> ~/.claude/CLAUDE.md
```

**Codex CLI** — no import syntax, so either symlink the file (if you have no other
global rules) or append a copy:

```bash
mkdir -p ~/.codex

# no global AGENTS.md yet → symlink, stays live
ln -s ~/code/skills/global-rules.md ~/.codex/AGENTS.md

# already have one → append a copy (re-run after each git pull)
cat ~/code/skills/global-rules.md >> ~/.codex/AGENTS.md
```

**opencode** — same two options, plus a third: list the file in the global config's
`instructions` array, which keeps it live without touching `AGENTS.md`:

```bash
mkdir -p ~/.config/opencode

# symlink
ln -s ~/code/skills/global-rules.md ~/.config/opencode/AGENTS.md

# or append a copy
cat ~/code/skills/global-rules.md >> ~/.config/opencode/AGENTS.md
```

```jsonc
// ~/.config/opencode/opencode.json
{
  "instructions": ["~/code/skills/global-rules.md"]
}
```

> Only Claude Code's `@`-import and opencode's `instructions` array read the file in
> place. Every `cat` line above is a **copy** — re-run it after a `git pull`, and
> delete the previous block first so the rules don't pile up twice.

## License

MIT — see [LICENSE](./LICENSE).
