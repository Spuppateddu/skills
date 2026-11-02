#!/usr/bin/env bash
#
# summarize.sh — summarize a text file with an LLM: a local one (llama.cpp,
# the default — nothing leaves the machine) or a cloud one (Claude, OpenAI,
# or whatever opencode is set up to use).
#
# Built for conversation transcripts — meetings, calls, interviews, lectures,
# tabletop RPG sessions — but works on any text.
# The summary is written in the SAME language as the input text.
#
# Usage:
#   ./summarize.sh [--backend NAME] [--model MODEL] <input.txt> [output.txt]
#   (default output: <input>-summary.txt)
#
# Backends (--backend, or SUMMARY_BACKEND):
#   local     llama.cpp + a GGUF model on this machine (default; offline)
#   claude    the `claude` CLI with its own login; without the CLI, the
#             Anthropic API with ANTHROPIC_API_KEY.            UPLOADS THE TEXT
#   openai    the OpenAI API with OPENAI_API_KEY.              UPLOADS THE TEXT
#   opencode  `opencode run`, with opencode's configured model. UPLOADS THE TEXT
#             (unless opencode itself points at a local model)
#
# Environment overrides:
#   SUMMARY_BACKEND=local               see above
#   SUMMARY_API_MODEL=...               model for a cloud backend (--model);
#                                       claude: sonnet / claude-sonnet-5-5,
#                                       openai: gpt-5-mini, opencode: its default
#   SUMMARY_MODEL=/path/to/model.gguf   model for the local backend
#   LLAMA_CLI=/path/to/llama-cli        llama.cpp binary
#   SUMMARY_MAXTOK=8192                 max tokens to generate (thinking + summary)
#   SUMMARY_RULES=/path/to/rules.md     summary rules added to every prompt
#
set -euo pipefail

# A summary is as private as the conversation it came from.
umask 077

SUMMARY_BACKEND="${SUMMARY_BACKEND:-local}"
SUMMARY_API_MODEL="${SUMMARY_API_MODEL:-}"
LLAMA_CLI="${LLAMA_CLI:-/mnt/large-language-model/engines/llama.cpp/build/bin/llama-cli}"
SUMMARY_MODEL="${SUMMARY_MODEL:-/mnt/large-language-model/models/general/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf}"
SUMMARY_MAXTOK="${SUMMARY_MAXTOK:-8192}"
SUMMARY_RULES="${SUMMARY_RULES:-}"
THREADS="$(nproc 2>/dev/null || echo 8)"

usage() {
    echo "Usage: summarize.sh [--backend local|claude|openai|opencode] [--model MODEL] <input.txt> [output.txt]" >&2
    exit 1
}

ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --backend)   [ $# -ge 2 ] || usage; SUMMARY_BACKEND="$2"; shift 2 ;;
        --backend=*) SUMMARY_BACKEND="${1#*=}"; shift ;;
        --model)     [ $# -ge 2 ] || usage; SUMMARY_API_MODEL="$2"; shift 2 ;;
        --model=*)   SUMMARY_API_MODEL="${1#*=}"; shift ;;
        -h|--help)   usage ;;
        *)           ARGS+=("$1"); shift ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

IN="${1:-}"
if [ -z "$IN" ] || [ ! -f "$IN" ]; then
    usage
fi
OUT="${2:-${IN%.*}-summary.txt}"

need() {  # $1 = command  $2 = why
    command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found — $2" >&2; exit 1; }
}

# Single-pass context cap per backend; inputs that don't fit are summarized
# map-reduce style in chunks. The local cap is what fits the model on an
# RTX 4070 12GB; the cloud ones stay well under their models' context windows.
case "$SUMMARY_BACKEND" in
    local)
        MAX_CTX=65536
        [ -x "$LLAMA_CLI" ]     || { echo "ERROR: llama-cli not found at $LLAMA_CLI (or pick a cloud backend with --backend)" >&2; exit 1; }
        [ -f "$SUMMARY_MODEL" ] || { echo "ERROR: model not found at $SUMMARY_MODEL (or pick a cloud backend with --backend)" >&2; exit 1; }
        ;;
    claude)
        MAX_CTX=150000
        if command -v claude >/dev/null 2>&1; then
            CLAUDE_VIA=cli;  SUMMARY_API_MODEL="${SUMMARY_API_MODEL:-sonnet}"
        elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            CLAUDE_VIA=api;  SUMMARY_API_MODEL="${SUMMARY_API_MODEL:-claude-sonnet-5-5}"
            need curl "needed to call the Anthropic API"; need jq "needed to read the API reply"
        else
            echo "ERROR: backend 'claude' needs the claude CLI (logged in) or ANTHROPIC_API_KEY." >&2; exit 1
        fi
        ;;
    openai)
        MAX_CTX=150000
        SUMMARY_API_MODEL="${SUMMARY_API_MODEL:-gpt-5-mini}"
        [ -n "${OPENAI_API_KEY:-}" ] || { echo "ERROR: backend 'openai' needs OPENAI_API_KEY." >&2; exit 1; }
        need curl "needed to call the OpenAI API"; need jq "needed to read the API reply"
        ;;
    opencode)
        MAX_CTX=100000
        need opencode "install it from opencode.ai"; need jq "needed to read opencode's output"
        ;;
    *)
        echo "ERROR: unknown backend '$SUMMARY_BACKEND' (local, claude, openai, opencode)." >&2; exit 1 ;;
esac
CHUNK_BYTES=$(( (MAX_CTX - SUMMARY_MAXTOK - 1024) * 2 ))   # ~3 bytes/token, with margin
if [ -n "$SUMMARY_RULES" ] && [ ! -f "$SUMMARY_RULES" ]; then
    echo "ERROR: rules file not found at $SUMMARY_RULES" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/llm.log"

# Every cloud backend gets the same system prompt: the instructions themselves
# travel in the prompt file, like for the local model.
SYSTEM_PROMPT='You summarize transcripts and other texts. Follow the instructions at the top of the input exactly. Output only the requested summary as plain text: no preamble, no closing remarks, no questions.'

# --- one generation per backend: $1=prompt-file, $2=context; prints clean text
run_local() {
    local prompt_file="$1" ctx="$2" raw="$WORK/raw.txt"
    "$LLAMA_CLI" \
        -m "$SUMMARY_MODEL" \
        -ngl 99 --n-cpu-moe 99 \
        -c "$ctx" -t "$THREADS" \
        --temp 0.4 -n "$SUMMARY_MAXTOK" \
        --single-turn --no-display-prompt \
        -f "$prompt_file" \
        > "$raw" 2> "$LOG"

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

run_claude() {
    local prompt_file="$1"
    if [ "$CLAUDE_VIA" = cli ]; then
        # A plain text-in/text-out call: no tools, no saved session, and none of
        # the user's CLAUDE.md files — their always-on rules (e.g. "end every
        # reply with a status line") would otherwise end up inside the summary.
        # Run from the scratch dir so no project CLAUDE.md is found either.
        ( cd "$WORK" && CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 claude -p \
            --model "$SUMMARY_API_MODEL" --tools "" --no-session-persistence \
            --setting-sources local --system-prompt "$SYSTEM_PROMPT" \
            < "$prompt_file" 2> "$LOG" )
    else
        jq -n --rawfile p "$prompt_file" --arg m "$SUMMARY_API_MODEL" \
              --arg s "$SYSTEM_PROMPT" --argjson n "$SUMMARY_MAXTOK" \
              '{model:$m, max_tokens:$n, system:$s, messages:[{role:"user", content:$p}]}' \
            > "$WORK/req.json"
        curl -sS --fail-with-body https://api.anthropic.com/v1/messages \
            -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
            -H "content-type: application/json" -d @"$WORK/req.json" \
            > "$WORK/reply.json" 2> "$LOG" || { cat "$WORK/reply.json" >> "$LOG"; return 1; }
        jq -r '[.content[] | select(.type=="text") | .text] | join("")' "$WORK/reply.json"
    fi
}

run_openai() {
    local prompt_file="$1"
    jq -n --rawfile p "$prompt_file" --arg m "$SUMMARY_API_MODEL" \
          --arg s "$SYSTEM_PROMPT" --argjson n "$SUMMARY_MAXTOK" \
          '{model:$m, max_completion_tokens:$n,
            messages:[{role:"system", content:$s}, {role:"user", content:$p}]}' \
        > "$WORK/req.json"
    curl -sS --fail-with-body https://api.openai.com/v1/chat/completions \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "content-type: application/json" -d @"$WORK/req.json" \
        > "$WORK/reply.json" 2> "$LOG" || { cat "$WORK/reply.json" >> "$LOG"; return 1; }
    jq -r '.choices[0].message.content // empty' "$WORK/reply.json"
}

run_opencode() {
    local prompt_file="$1"
    # The text goes in as an attached file: a long transcript is larger than
    # the 128 KB the kernel allows for one command-line argument.
    # The message goes BEFORE -f: -f takes a list and would swallow it as a
    # second file name. stdin is closed so opencode never waits on it.
    ( cd "$WORK" && opencode run --pure --format json \
        ${SUMMARY_API_MODEL:+-m "$SUMMARY_API_MODEL"} \
        "$SYSTEM_PROMPT The input is the attached file." -f "$prompt_file" \
        < /dev/null \
        > "$WORK/reply.jsonl" 2> "$LOG" )
    jq -rj 'select(.type=="text") | .part.text' "$WORK/reply.jsonl"
    echo
}

run_llm() {  # $1=prompt-file  $2=context (only the local backend uses it)
    local out
    out="$("run_$SUMMARY_BACKEND" "$1" "$2")" || {
        echo "ERROR: the '$SUMMARY_BACKEND' backend failed:" >&2
        tail -n 20 "$LOG" >&2 || true
        exit 1
    }
    printf '%s\n' "$out"
}

# --- prompt templates ---------------------------------------------------------
SHARED_CONTEXT='The transcript comes from a recorded conversation — a meeting, a work call, an interview, a lesson, a tabletop RPG session — automatically transcribed from audio, so it may contain transcription errors: silently fix them from context.
Lines may start with a timestamp and a speaker label such as [ME] (the person who recorded) or [THEM] (everyone else). Use those to tell who said what, but do not copy the labels into the summary.'

FULL_INSTRUCTIONS="You will receive the transcript of a recorded conversation.
$SHARED_CONTEXT
Write a thorough summary: what the conversation was about, the main points and events in chronological order, decisions taken, questions asked and the answers given, names, numbers and dates mentioned, disagreements, and anything left unresolved. If the conversation produced tasks or next steps, list them at the end.
Ignore small talk and off-topic chatter.
IMPORTANT: write the summary in the SAME LANGUAGE as the transcript. Output only the summary, no preamble."

CHUNK_INSTRUCTIONS="You will receive ONE PART of a longer transcript of a recorded conversation.
$SHARED_CONTEXT
Write a detailed chronological summary of everything relevant in this part: topics, points made, decisions, questions and answers, names, numbers and dates, and any task or next step mentioned. Ignore small talk and off-topic chatter.
IMPORTANT: write in the SAME LANGUAGE as the transcript. Output only the summary, no preamble."

REDUCE_INSTRUCTIONS='You will receive, in order, partial summaries of consecutive parts of ONE recorded conversation.
Merge them into a single thorough summary of the whole conversation: what it was about, the main points and events in chronological order, decisions taken, questions and their answers, names, numbers and dates mentioned, disagreements, and anything left unresolved. If there were tasks or next steps, list them at the end. Remove repetitions between the parts.
IMPORTANT: write in the SAME LANGUAGE as the partial summaries. Output only the summary, no preamble.'

# The user's rules go last, so where they differ from the instructions above
# they win. The chunk prompt gets them too: a rule about what to leave out or
# how to spell a name has to hold before the merge, not only after it.
if [ -n "$SUMMARY_RULES" ]; then
    RULES_BLOCK="
Follow these rules from the user. Where they differ from the instructions above, the rules win:
$(cat "$SUMMARY_RULES")"
    FULL_INSTRUCTIONS="$FULL_INSTRUCTIONS$RULES_BLOCK"
    CHUNK_INSTRUCTIONS="$CHUNK_INSTRUCTIONS$RULES_BLOCK"
    REDUCE_INSTRUCTIONS="$REDUCE_INSTRUCTIONS$RULES_BLOCK"
    echo "==> Using summary rules from '$SUMMARY_RULES'"
fi

# --- decide single-pass vs map-reduce ----------------------------------------
BYTES="$(stat -c%s "$IN")"
EST_TOKENS=$(( BYTES / 3 ))                       # conservative across languages
NEED_CTX=$(( EST_TOKENS + SUMMARY_MAXTOK + 1024 ))
[ "$NEED_CTX" -lt 16384 ] && NEED_CTX=16384

if [ "$NEED_CTX" -le "$MAX_CTX" ]; then
    echo "==> Summarizing '$IN' (~$EST_TOKENS tokens, single pass, backend: $SUMMARY_BACKEND)..."
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

# Blank lines only count as empty too: a backend that answered nothing still
# leaves a newline or two behind.
if ! grep -q '[^[:space:]]' "$OUT" 2>/dev/null; then
    echo "ERROR: empty summary. Model log:" >&2
    cat "$LOG" >&2 || true
    exit 1
fi
echo "==> Summary saved: $OUT"
