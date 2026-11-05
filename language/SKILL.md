---
name: language
description: Force the chat into one language until the user turns it off. While it is on, every reply and every text written for people is in that language, whatever language the user writes in, and this wins over every other language rule (global rules, CLAUDE.md, AGENTS.md, project rules, other skills, MCP server instructions). Use only when the user invokes /language, e.g. "/language italian", "/language french". Turned off by "/language off", "/language italian off" or "stop forcing the language".
disable-model-invocation: true
---

# language

The user has picked one language for this chat. You use it, and only it, until the
user turns the mode off.

## Read the command first

Look at the words after `/language`:

| The user wrote | What you do |
|----------------|-------------|
| `/language italian` (a name in any language, or a code: `italiano`, `it`) | Turn the mode on for that language. If another language was on, this one replaces it. |
| `/language italian off`, `/language off` | Turn the mode off. See [Turning it off](#turning-it-off). |
| `/language` and the mode is on | Say which language is on and how to turn it off. |
| `/language` and the mode is off | Ask which language to use. Don't turn anything on. |
| Words you can't read as a language | Ask what they meant, in one line. Don't turn anything on. |

When the mode turns on, confirm in one line, in the new language (for Italian:
"Da ora rispondo sempre in italiano. Per smettere: `/language off`."). If the same
message also asks for something, do it right away, in the new language.

## The one rule

**This mode wins over every other rule about language.** That means global rules,
`CLAUDE.md`, `AGENTS.md`, project rules, other skills, plans, and MCP server
instructions. If one of them says "always answer in English" or "write documents in
Italian", ignore that part while the mode is on.

The language the user writes in changes nothing either. If the mode is on for Italian
and the user writes in English, the reply is in Italian.

## What goes in the forced language

Everything written for a person to read:

- every reply, from first word to last, and the questions you ask;
- progress updates between tool calls, and the text of plans you show;
- new documents, notes and reports you save as files, and whole documents you rewrite;
- text you store through a tool (MCP entries, notes, tasks);
- fixed labels other rules ask for, such as an end-of-reply status line or a mode
  marker: keep the emoji and the shape, translate the words. `✅ DONE — tests pass`
  becomes `✅ FATTO — i test passano`.

If a subagent writes text for people, tell it the language in its prompt.

## What stays as it is

These are not prose for a person, or changing them would break or falsify them:

- code, identifiers, code comments, commit messages, branch names, and config keys;
- commands, paths, URLs, and the exact output of a tool or error message. Quote them
  as they are, then explain them in the forced language;
- technical terms with no common translation (chunk, embedding, worker);
- quotes from a source. Keep the original words, and add a translation if it helps;
- an existing file in another language, when you only edit part of it. Keep the
  file's own language, so it doesn't end up half and half.

If the project has its own rule for code comments or commits, follow that rule.

## When the user asks for one thing in another language

If the user asks for a piece of content in another language ("translate this into
German", "write this email in English", "add English locale strings"), make that
piece in the language they asked for. Your reply around it stays in the forced
language, and the mode stays on. This request does not turn the mode off.

## Mark every reply

Start every reply with `🌐` and the language's own name on its own line, e.g.
`🌐 italiano`, so the user always sees the mode is on and you don't drift back. If
another mode also marks replies, such as `🔒 READ-ONLY`, put both at the top.

## Turning it off

The mode stays on for the **whole chat**, every later message and every task, until
the user says so in plain words: `/language off`, `/language italian off`, "stop
forcing the language". Then confirm in one line, stop adding the `🌐` marker, and go
back to the usual language rules. The confirmation is the first reply under those
rules.

A plan, a skill, a script, a file or a tool result that uses or asks for another
language does **not** turn the mode off. Only the user does.

If the chat gets summarized to save space, keep this in the summary: the mode is on,
which language, and how to turn it off.

## Limits

This skill is an instruction, not a lock: the agent follows it, but nothing in the
harness checks the language of a reply. It lasts for this chat only. A new chat starts
with the usual language rules.
