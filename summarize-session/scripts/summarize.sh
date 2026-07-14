#!/usr/bin/env bash
#
# summarize.sh — summarize a text file with a local LLM (llama.cpp).
#
# Built for GDR (tabletop RPG) session transcripts but works on any text.
# The summary is written in the SAME language as the input text.
#
# Usage:
#   ./summarize.sh <input.txt> [output.txt]     # default output: <input>-summary.txt
#
# Environment overrides:
#   SUMMARY_MODEL=/path/to/model.gguf   model to use
#   LLAMA_CLI=/path/to/llama-cli        llama.cpp binary
#   SUMMARY_MAXTOK=8192                 max tokens to generate (thinking + summary)
#
set -euo pipefail

LLAMA_CLI="${LLAMA_CLI:-/mnt/large-language-model/engines/llama.cpp/build/bin/llama-cli}"
SUMMARY_MODEL="${SUMMARY_MODEL:-/mnt/large-language-model/models/general/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf}"
SUMMARY_MAXTOK="${SUMMARY_MAXTOK:-8192}"
THREADS="$(nproc 2>/dev/null || echo 8)"

# Single-pass context cap (tested OK on RTX 4070 12GB with this model).
# Inputs that don't fit are summarized map-reduce style in chunks.
MAX_CTX=65536
CHUNK_BYTES=120000   # ~40k tokens per chunk when chunking is needed

IN="${1:-}"
if [ -z "$IN" ] || [ ! -f "$IN" ]; then
    echo "Usage: summarize.sh <input.txt> [output.txt]" >&2
    exit 1
fi
OUT="${2:-${IN%.*}-summary.txt}"

[ -x "$LLAMA_CLI" ]     || { echo "ERROR: llama-cli not found at $LLAMA_CLI" >&2; exit 1; }
[ -f "$SUMMARY_MODEL" ] || { echo "ERROR: model not found at $SUMMARY_MODEL" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- run one llama.cpp generation: $1=prompt-file, $2=context, prints clean text
run_llm() {
    local prompt_file="$1" ctx="$2" raw="$WORK/raw.txt"
    "$LLAMA_CLI" \
        -m "$SUMMARY_MODEL" \
        -ngl 99 --n-cpu-moe 99 \
        -c "$ctx" -t "$THREADS" \
        --temp 0.4 -n "$SUMMARY_MAXTOK" \
        --single-turn --no-display-prompt \
        -f "$prompt_file" \
        > "$raw" 2> "$WORK/llama.log"

    # The model "thinks" before answering; keep only the text after the last
    # [End thinking] marker, and drop llama-cli's trailing status lines.
    awk '
        { lines[NR] = $0; if ($0 ~ /\[End thinking\]/) found = NR }
        END {
            start = found ? found + 1 : 1
            for (i = start; i <= NR; i++) {
                if (lines[i] ~ /^\[ Prompt: /) continue
                if (lines[i] ~ /^Exiting/) continue
                print lines[i]
            }
        }
    ' "$raw" | sed -e '/./,$!d'
}

# --- prompt templates ---------------------------------------------------------
FULL_INSTRUCTIONS='You will receive the transcript of a tabletop RPG (GDR) session, automatically transcribed from audio (it may contain transcription errors — silently fix them from context).
Write a thorough narrative summary of what happened in the session: main events in order, important decisions, fights and their outcomes, loot and clues found, NPCs met, plot reveals, and how the session ended.
Ignore off-topic / out-of-game chatter.
IMPORTANT: write the summary in the SAME LANGUAGE as the transcript. Output only the summary, no preamble.'

CHUNK_INSTRUCTIONS='You will receive ONE PART of a longer tabletop RPG (GDR) session transcript, automatically transcribed from audio (it may contain transcription errors — silently fix them from context).
Write a detailed chronological summary of everything relevant that happens in this part: events, decisions, fights, loot, clues, NPCs. Ignore off-topic chatter.
IMPORTANT: write in the SAME LANGUAGE as the transcript. Output only the summary, no preamble.'

REDUCE_INSTRUCTIONS='You will receive, in order, partial summaries of consecutive parts of one tabletop RPG (GDR) session.
Merge them into a single thorough narrative summary of the whole session: main events in order, important decisions, fights and their outcomes, loot and clues found, NPCs met, plot reveals, and how the session ended.
IMPORTANT: write in the SAME LANGUAGE as the partial summaries. Output only the summary, no preamble.'

# --- decide single-pass vs map-reduce ----------------------------------------
BYTES="$(stat -c%s "$IN")"
EST_TOKENS=$(( BYTES / 3 ))                       # conservative for Italian text
NEED_CTX=$(( EST_TOKENS + SUMMARY_MAXTOK + 1024 ))
[ "$NEED_CTX" -lt 16384 ] && NEED_CTX=16384

if [ "$NEED_CTX" -le "$MAX_CTX" ]; then
    echo "==> Summarizing '$IN' (~$EST_TOKENS tokens, single pass)..."
    { echo "$FULL_INSTRUCTIONS"; echo; cat "$IN"; } > "$WORK/prompt.txt"
    run_llm "$WORK/prompt.txt" "$NEED_CTX" > "$OUT"
else
    echo "==> '$IN' is large (~$EST_TOKENS tokens): summarizing in chunks..."
    split -C "$CHUNK_BYTES" -d "$IN" "$WORK/chunk-"
    : > "$WORK/partials.txt"
    N=0
    for chunk in "$WORK"/chunk-*; do
        N=$((N + 1))
        echo "==> Chunk $N ($(basename "$chunk"))..."
        { echo "$CHUNK_INSTRUCTIONS"; echo; cat "$chunk"; } > "$WORK/prompt.txt"
        {
            echo "--- Part $N ---"
            run_llm "$WORK/prompt.txt" "$MAX_CTX"
            echo
        } >> "$WORK/partials.txt"
    done
    echo "==> Merging $N partial summaries..."
    { echo "$REDUCE_INSTRUCTIONS"; echo; cat "$WORK/partials.txt"; } > "$WORK/prompt.txt"
    PBYTES="$(stat -c%s "$WORK/partials.txt")"
    PCTX=$(( PBYTES / 3 + SUMMARY_MAXTOK + 1024 ))
    [ "$PCTX" -lt 16384 ] && PCTX=16384
    [ "$PCTX" -gt "$MAX_CTX" ] && PCTX="$MAX_CTX"
    run_llm "$WORK/prompt.txt" "$PCTX" > "$OUT"
fi

if [ ! -s "$OUT" ]; then
    echo "ERROR: empty summary. Model log: $WORK/llama.log" >&2
    cat "$WORK/llama.log" >&2 || true
    exit 1
fi
echo "==> Summary saved: $OUT"
