---
name: summarize-transcript
description: Summarize a transcript — a meeting, a work call, an interview, a lecture, a tabletop-RPG session — or any other text file, with a local LLM (llama.cpp + Qwen3.5-35B-A3B on the large-language-model disk; the default, nothing uploaded) or, when the user asks for it, a cloud one — Claude (claude CLI or Anthropic API), OpenAI (API), or opencode. The summary is written in the same language as the input and saved as a .txt next to it. Pairs with the call-transcriber repo, which produces those transcripts. Use when the user asks to summarize a transcript, a call, a meeting, an interview, a session or a text file, e.g. "summarize this call", "riassumi la riunione", "make a summary of transcript.txt", "summarize it with Claude", "use opencode for the summary".
---

# summarize-transcript

Summarize a `.txt` file with an LLM. By default it is the **local** model:
everything runs offline on this machine and nothing is uploaded — which is the
point when the text is a client call, an interview, or a private conversation.
On request it can use a **cloud** model instead: Claude, OpenAI, or whatever
opencode is set up with.

Built for the transcripts produced by
[call-transcriber](https://github.com/Spuppateddu/call-transcriber)
(`sessions/<timestamp>/transcript.txt`, with `[ME]` / `[THEM]` speaker labels),
but it takes any text file.

## How to run

```bash
bash "$(dirname "$0")/scripts/summarize.sh" [--backend NAME] [--model MODEL] <input.txt> [output.txt]
```

- Default output: `<input>-summary.txt` next to the input file, private (`0600`).
- The script picks single-pass or chunked (map-reduce) summarization
  automatically based on input size, extracts the model's final answer
  (dropping its thinking section), and writes clean text.

## Backends

| `--backend` | Uses | Needs | Uploads the text? |
|---|---|---|---|
| `local` (default) | llama.cpp + the GGUF model | the `/mnt/large-language-model` disk | **no** |
| `claude` | the `claude` CLI with its own login; without the CLI, the Anthropic API | `claude` logged in, or `ANTHROPIC_API_KEY` | yes, to Anthropic |
| `openai` | the OpenAI chat completions API | `OPENAI_API_KEY` | yes, to OpenAI |
| `opencode` | `opencode run` with opencode's configured model | `opencode` | yes, to that model's provider (unless it is a local one) |

`--model` picks the model for a cloud backend: a Claude alias or id
(`sonnet` by default, `opus`, `haiku`…), an OpenAI model (`gpt-5-mini` by
default), or opencode's `provider/model` (`opencode models` lists them).

**Privacy rule for the agent:** use a cloud backend only when the user asked for
it (by name, or by saying cloud/API is fine). If the user did not say and the
local backend is not available on this machine, **ask** which backend to use —
never upload a transcript on your own initiative.

Timing: the local backend takes roughly 1–3 minutes for a one-hour transcript
(~49 tok/s generation, ~400 tok/s reading on an RTX 4070). Cloud backends read
much longer inputs in one pass (fewer chunks); free opencode models can be slow.

## Typical flow

1. If the user points at a call-transcriber session directory
   (`sessions/<timestamp>/`), the input is its `transcript.txt`.
2. Pick the backend (see the privacy rule above). Run the script and wait for
   it to finish (give the Bash call a generous timeout: 10+ minutes for long
   transcripts).
3. Read the resulting summary file and show the user a short preview plus the
   output path. Do not rewrite or "improve" the summary — the user wants the
   model's output.

## Configuration (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `SUMMARY_BACKEND` | `local` | backend, same as `--backend` |
| `SUMMARY_API_MODEL` | per backend (see above) | cloud model, same as `--model` |
| `SUMMARY_MODEL` | `/mnt/large-language-model/models/general/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf` | GGUF model for `local` |
| `LLAMA_CLI` | `/mnt/large-language-model/engines/llama.cpp/build/bin/llama-cli` | llama.cpp binary for `local` |
| `SUMMARY_MAXTOK` | `8192` | max tokens generated (thinking + summary) |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | — | API keys for `claude` (without the CLI) / `openai` |

## Troubleshooting

- **"model not found" / "llama-cli not found"** — the `/mnt/large-language-model`
  disk is not mounted, the model was moved, or this machine simply has no local
  model; check with `ls /mnt/large-language-model/models/general/`, or (with
  the user's OK) use a cloud backend.
- **A cloud backend fails** — the script prints the last lines of its log:
  usually a missing login (`claude`, `opencode auth login`) or a wrong API key
  or model name.
- **Very slow (local)** — another process is using the GPU (check `nvidia-smi`);
  summarize once it's free.
- **Summary in the wrong language** — the model mirrors the input language;
  if the transcript is mixed-language, the dominant one wins.
