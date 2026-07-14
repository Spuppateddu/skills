---
name: summarize-session
description: Summarize a text file with a fully local LLM (llama.cpp + Qwen3.5-35B-A3B on the large-language-model disk) — built for GDR/tabletop-RPG session transcripts produced by GDR-Live-Transcriber, but works on any text file. The summary is written in the same language as the input and saved as a .txt next to it. Use when the user asks to summarize a session, a transcript, or a text file locally, e.g. "summarize this session", "riassumi la sessione", "make a summary of transcript.txt".
---

# summarize-session

Summarize a `.txt` file with the local model. Everything runs offline on this
machine; nothing is uploaded anywhere.

## How to run

```bash
bash "$(dirname "$0")/scripts/summarize.sh" <input.txt> [output.txt]
```

- Default output: `<input>-summary.txt` next to the input file.
- The script picks single-pass or chunked (map-reduce) summarization
  automatically based on input size, extracts the model's final answer
  (dropping its thinking section), and writes clean text.
- Expect roughly 1–3 minutes for a normal session transcript; several minutes
  for very long ones (the model generates at ~49 tok/s and reads at
  ~400 tok/s on this machine's RTX 4070).

## Typical flow

1. If the user points at a GDR-Live-Transcriber session directory
   (`sessions/<timestamp>/`), the input is its `transcript.txt`.
2. Run the script and wait for it to finish (give the Bash call a generous
   timeout: 10+ minutes for long transcripts).
3. Read the resulting summary file and show the user a short preview plus the
   output path. Do not rewrite or "improve" the summary — the user wants the
   local model's output.

## Configuration (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `SUMMARY_MODEL` | `/mnt/large-language-model/models/general/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf` | GGUF model to use |
| `LLAMA_CLI` | `/mnt/large-language-model/engines/llama.cpp/build/bin/llama-cli` | llama.cpp binary |
| `SUMMARY_MAXTOK` | `8192` | max tokens generated (thinking + summary) |

## Troubleshooting

- **"model not found"** — the `/mnt/large-language-model` disk is not mounted
  or the model was moved; check with `ls /mnt/large-language-model/models/general/`.
- **Very slow** — another process is using the GPU (check `nvidia-smi`);
  summarize after closing the game.
- **Summary in the wrong language** — the model mirrors the input language;
  if the transcript is mixed-language, the dominant one wins.
