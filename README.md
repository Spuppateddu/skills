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

**Supported OS:** Linux and macOS. Requirements: `bash`, `git`, `curl`, `jq`
(`apt install jq` / `brew install jq`). The scripts avoid bash 4+ features, so
macOS's default bash 3.2 works.

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

## Adding a skill

1. Create `my-skill/SKILL.md` with YAML frontmatter (`name`, `description`) — the
   `description` is the trigger, so make it specific.
2. Bundle any helper scripts under `my-skill/scripts/`, referenced **relative to the
   skill folder** (never hardcode `.claude/...`, so it stays portable).
3. Commit and push; consumers get it via `openskills sync` or `git pull`.

## License

MIT — see [LICENSE](./LICENSE).
