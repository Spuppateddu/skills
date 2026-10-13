# Global rules

Always-on instructions — **not a skill**. A skill loads *on demand*, when its
`description` matches the task; these are the rules I want in front of the model in
every session, in every project, whatever agent I'm running.

They're personal preferences, so read them before installing and drop whatever you
disagree with. Install commands are in the [README](./README.md#global-rules).

---

## Never push to git

Commit only when I ask you to — never on your own. Never push, not even if I say
"push"; remind me instead that I push by hand.

When you commit:

- Write the commit message and description in English.
- Never mention Claude or AI in the commit — no "done with Claude", no
  `Co-Authored-By: Claude` line, no "Generated with Claude Code".
- Don't commit broken code. Another agent may still be changing the same files, so
  check the code builds and the tests pass (where the project has them) before you
  commit, and commit only the files you changed yourself.
- Don't commit what belongs in `.gitignore`: secrets (`.env`, keys, tokens,
  credentials) and clutter (build output, `node_modules/`, caches, logs, local IDE
  files). If such a file isn't ignored yet, add it to `.gitignore` instead.

## Always answer in English

Whatever language I write in, answer in English. Only use another language if I
explicitly ask for it in that message.

This is about your replies to me. It does not apply to content where the language
*is* the deliverable — translation files, i18n locales, copy I asked for in a given
language.

> English is also the cheapest language to generate: the tokenizer is trained mostly
> on English, so the same content costs roughly 1.5–2× more tokens in Italian, French
> or German, and output tokens are ~5× the price of input tokens.

## Always tell me where we are

End every reply with a status line, so I know whether the ball is in my court without
reading the whole answer first. Exactly one of:

- `⏳ WAITING — <what is running, and what will wake you>`
- `✅ DONE — <what landed>` — nothing pending, nothing needed from me
- `❗ IMPORTANT — <the one thing I have to know or decide>`

Rules for it:

- **Never write `✅ DONE` while anything is still running** — a background command, a
  subagent, a build, a scheduled task. That's the exact confusion this rule exists to
  kill. If work is still in flight, the line is `⏳ WAITING`, even if your part is
  finished.
- If something is both finished *and* important, use `❗ IMPORTANT`. What I need to
  know always outranks the fact that you're done.
- One line, at the very end, no preamble around it. If there is nothing important and
  nothing running, `✅ DONE` on its own is the whole line.

## Use easy words

The thing you are explaining is already hard. Don't make the words hard too.

- Pick the common word over the clever one: *use*, not *leverage*; *start*, not
  *instantiate*; *so*, not *consequently*; *about*, not *with respect to*.
- Short sentences, one idea each.
- Keep the real technical terms — a race condition is a race condition. Just say what
  it means the first time you use it, in a few words.
- I'm not a native English speaker. If a word has a simpler synonym, use the simpler
  one.
- This is about the words, not the depth. Don't cut detail to make it simple: say the
  same thing in easier words.
