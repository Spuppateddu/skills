# Local skills

This folder holds **your own skills that are never committed**. Use it for things that
only make sense on your machine: a client's deploy steps, private server names, a
half-finished idea, a tweak you don't want to share.

Git ignores everything in here except this README, so local skills don't show in
`git status` and `git add -A` can't pick them up by mistake.

```
skills/
├── branch-review/          ← shared, committed
├── plan-write/             ← shared, committed
├── deploy-acme -> local/deploy-acme    ← link, so the agent finds it (not committed)
└── local/
    ├── README.md           ← this file, committed
    └── deploy-acme/        ← your skill, ignored by git
        ├── SKILL.md
        └── scripts/
```

## Why the link

Agents look for skills **one level deep**: `~/.claude/skills/<folder>/SKILL.md`. With
the clone linked as `~/.claude/skills` (see [Setup](../README.md#setup)), a skill in
`local/deploy-acme/` sits two levels deep and the agent would never find it. A link at
the top of the repo puts it back where the agent looks.

The link must not be committed either. So you list it in `.git/info/exclude`: it works
like `.gitignore`, but it lives inside `.git/`, so it never leaves your machine.

## Create a local skill

From the repo root, with `deploy-acme` as the example name (lowercase letters, digits
and hyphens):

```bash
# 1. the skill folder
mkdir -p local/deploy-acme

# 2. the SKILL.md — `name` must match the folder name
cat > local/deploy-acme/SKILL.md <<'EOF'
---
name: deploy-acme
description: Deploy the Acme app to staging. Use when the user says "deploy acme".
---

# deploy-acme

The steps the model should follow.
EOF

# 3. link it to the top level, so the agent finds it
ln -s local/deploy-acme deploy-acme

# 4. keep the link out of git, on this machine only
echo '/deploy-acme' >> .git/info/exclude
```

The `description` decides when the model loads the skill, so write it as the words
you'd actually type. Start a new agent session to pick the skill up.

Pick a name no shared skill uses: if `git pull` brings in a folder with the same name,
it clashes with your link.

## Check it is ignored

```bash
git status                  # neither local/deploy-acme nor the link shows up
git check-ignore -v deploy-acme local/deploy-acme/SKILL.md
```

## Remove a local skill

```bash
rm deploy-acme              # the link (no trailing slash, or you delete the target)
rm -r local/deploy-acme
```

Then delete its `/deploy-acme` line from `.git/info/exclude`.

## Things to know

- **No backup.** Git doesn't track these files, so a lost disk or a fresh clone loses
  them. If a skill matters, keep a copy somewhere safe.
- **`git clean -X` / `-x` deletes them.** Both remove ignored files. Plain
  `git clean -fd` is safe.
- **Installers skip them.** `npx openskills install Spuppateddu/skills` pulls from
  GitHub, so local skills only exist where you made them.
- **Share it later** by moving it out of `local/`: `rm deploy-acme`, then
  `mv local/deploy-acme .`, then delete its line from `.git/info/exclude`. It now shows
  up in `git status`, ready to commit.
