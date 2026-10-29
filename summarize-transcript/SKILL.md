---
name: summarize-transcript
description: Summarize a transcript — a meeting, a work call, an interview, a lecture, a tabletop-RPG session — or any other text file. By default the agent you are chatting with writes the summary itself, with the model it is running on; another model or tool (a fully local llama.cpp model, another agent CLI) is used only when the user asks for it. Follows the user's summary rules — one or more files in a summary-rules.md / summary-rules/ folder where the chat was started, or in a path the user gives — picking the file that fits the transcript (work call, RPG session…). The summary is written in the same language as the input and saved as a .txt next to it. Pairs with the call-transcriber repo, which produces those transcripts. Use when the user asks to summarize a transcript, a call, a meeting, an interview, a session or a text file, e.g. "summarize this call", "riassumi la riunione", "make a summary of transcript.txt".
---

# summarize-transcript

Summarize a `.txt` file — usually a transcript made by
[call-transcriber](https://github.com/Spuppateddu/call-transcriber)
(`sessions/<timestamp>/transcript.txt`, with `[ME]` / `[THEM]` speaker labels),
but any text file works.

## 1. Which model writes the summary

**Default: you.** The summary is written by the agent the user is chatting with,
on the model it is running right now. Claude Code uses its current Claude model,
Codex its current model, and so on. Do **not** ask the user which model to use,
and do not run the local script "to be safe". Just read the file and write the
summary.

Use something else **only when the user asks for it** in the request:

| The user asks for… | Do this |
|---|---|
| a local / offline model, "llama", "Qwen", "nothing must leave this machine" | Run `scripts/summarize.sh` (see [Local model](#local-model-llamacpp)). |
| another agent or tool (e.g. "use codex", "use claude", "use gemini") | Check it is installed (`command -v codex`), then run it non-interactively — `codex exec`, `claude -p`, `gemini -p` — with the same instructions, the rules (step 2) and the transcript path. Save its answer as the summary file. |
| another model of the same tool (e.g. "use opus", "use a smaller model") | If you can start a subagent on that model, give it the job. If you can't, tell the user how to switch (`/model` in Claude Code or Codex) and stop. |

If the tool or model the user asked for is not available, say so and stop. Never
fall back to another model without telling the user.

Privacy note: with the default, the transcript goes to the provider of the model
you run on (if it is a cloud model). That is what the user chose by opening the
chat there. If they want nothing to leave the machine, they ask for the local
model.

## 2. Find the summary rules

Rules decide what the summary looks like: format, sections, length, what to
leave out, names to spell right, and so on. There can be **several rules
files**, one per kind of transcript (e.g. `lavoro.md` for work calls, `gdr.md`
for RPG sessions). Each one should say near the top what it is for.

A **rules place** is a folder that holds a `summary-rules.md` file, a
`summary-rules/` folder of `.md` files, or both. Every `.md` found there is one
candidate rules file.

Find the rules place **before** you write anything — the first one found wins:

1. **A path in the user's request** ("use the rules in ~/work/rules.md",
   "follow the rules in ~/clients/acme/"). A file: that is the rules file, skip
   to the end of this step. A folder: it is the rules place (if it holds `.md`
   files directly, those are the candidates too). If the path does not exist,
   say so and stop — do not silently use the defaults.
2. **The folder where the chat was started** (the agent's working directory,
   not the transcript's folder), if it holds `summary-rules.md` or
   `summary-rules/`.
3. **None found:** use the default rules below.

Then pick **one** rules file from the candidates:

- The user named one ("con le regole gdr", "use the work rules"): use the file
  whose name or "what it is for" line matches. No match: list the candidates
  and ask.
- Only one candidate: use it.
- Several, none named: read the top of each and use the one whose purpose
  clearly fits this transcript (an RPG session → the RPG rules). If none
  clearly fits, or two do, list them and ask which one.

Read the whole chosen file and follow it. Where it says something different
from the default rules, the file wins — including the format: if it asks for
plain text with no markdown, write none. Tell the user in one line which rules
file you used, or that you used the defaults.

### Default rules

- Write the summary in the **same language as the transcript**.
- The text comes from speech-to-text, so it has transcription errors: fix them
  silently from context.
- Lines can start with a timestamp and a speaker label: `[ME]` is the person who
  recorded, `[THEM]` is everyone else. Use them to tell who said what; do not
  copy the labels into the summary.
- Cover: what the conversation was about, the main points and events in
  chronological order, decisions taken, questions asked and the answers given,
  names, numbers and dates, disagreements, and anything left open.
- If the conversation produced tasks or next steps, list them at the end.
- Leave out small talk and off-topic chatter.
- Output only the summary, with no preamble.

## 3. Write it

1. If the user points at a call-transcriber session folder
   (`sessions/<timestamp>/`), the input is its `transcript.txt`.
2. Read the **whole** transcript. A long one does not fit in one read: read it
   in parts, take notes per part, then write one summary from the notes.
3. Save the summary as `<input>-summary.txt` next to the input
   (`transcript.txt` → `transcript-summary.txt`), unless the user or the rules
   name another path. If the file already exists, ask before overwriting it.
4. Show the user a short preview and the output path.

## Local model (llama.cpp)

Only when the user asks for it (step 1). Everything runs offline on this
machine.

```bash
SUMMARY_RULES=<rules-file> bash "<skill-dir>/scripts/summarize.sh" <input.txt> [output.txt]
```

- Pass the one rules file picked in step 2 as `SUMMARY_RULES`; leave it unset
  when there is none. The script adds the rules to every prompt it sends.
- Default output: `<input>-summary.txt` next to the input file.
- The script picks single-pass or chunked (map-reduce) summarization
  automatically based on input size, drops the model's thinking section, and
  writes clean text.
- Expect roughly 1–3 minutes for a normal one-hour transcript; several minutes
  for very long ones (the model generates at ~49 tok/s and reads at ~400 tok/s
  on this machine's RTX 4070). Give the Bash call a generous timeout: 10+
  minutes for long transcripts.
- Show the user the summary as the local model wrote it. Do not rewrite or
  "improve" it — they asked for that model's output.

| Variable | Default | Meaning |
|---|---|---|
| `SUMMARY_MODEL` | `/mnt/large-language-model/models/general/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf` | GGUF model to use |
| `LLAMA_CLI` | `/mnt/large-language-model/engines/llama.cpp/build/bin/llama-cli` | llama.cpp binary |
| `SUMMARY_MAXTOK` | `8192` | max tokens generated (thinking + summary) |
| `SUMMARY_RULES` | *(unset)* | rules file added to every prompt |

Troubleshooting:

- **"model not found"** — the `/mnt/large-language-model` disk is not mounted
  or the model was moved; check with `ls /mnt/large-language-model/models/general/`.
- **Very slow** — another process is using the GPU (check `nvidia-smi`);
  summarize once it's free.
- **Summary in the wrong language** — the model mirrors the input language;
  if the transcript is mixed-language, the dominant one wins.
