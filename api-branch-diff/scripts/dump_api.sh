#!/usr/bin/env bash
#
# Fire a set of API endpoints with curl and dump each response `data` payload to a
# file, so the same endpoints can be compared across git branches.
#
# Requires the app to be running and reachable at BASE_URL. Needs `jq`.
#
#   BASE_URL=http://localhost:8000 ENDPOINTS_FILE=/abs/endpoints.json \
#     BRANCH_TAG=mybranch DUMP_DIR=/abs/out bash dump_api.sh
#
# ENDPOINTS_FILE: JSON object { "name": "/path", ... } (paths only)
# BASE_URL:       base URL the paths are appended to
# BRANCH_TAG:     suffix for output files (e.g. the branch name)
# DUMP_DIR:       directory the <name>.<tag>.json files are written to
# VOLATILE:       optional comma-separated meta keys to drop (when no `data` envelope)
#
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

BASE_URL="${BASE_URL:?BASE_URL is required (e.g. http://localhost:8000)}"
ENDPOINTS_FILE="${ENDPOINTS_FILE:?ENDPOINTS_FILE is required}"
TAG="${BRANCH_TAG:-run}"
DIR="${DUMP_DIR:-$PWD}"
VOLATILE="${VOLATILE:-cached_at,cached_ttl,cached_exp,duration,request}"

[ -r "$ENDPOINTS_FILE" ] || { echo "ERROR: cannot read endpoints from $ENDPOINTS_FILE" >&2; exit 1; }

# Branch names may contain slashes; keep the tag filename-safe.
TAG="$(printf '%s' "$TAG" | tr -c 'A-Za-z0-9._-' '-')"
BASE_URL="${BASE_URL%/}"
mkdir -p "$DIR"

# Build a jq filter that deletes each volatile key from .meta (used when no `data`).
strip_filter='if has("data") then .data else (if (.meta? | type) == "object" then '
IFS=',' read -ra _keys <<< "$VOLATILE"
for k in "${_keys[@]}"; do
  [ -n "$k" ] && strip_filter+="del(.meta.\"$k\") | "
done
strip_filter+='. else . end) end'

# Iterate the endpoints map: name<TAB>path
jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$ENDPOINTS_FILE" | while IFS=$'\t' read -r name path; do
  out="$DIR/$name.$TAG.json"
  body="$(curl -s -w '\n%{http_code}' "$BASE_URL$path")"
  status="${body##*$'\n'}"
  body="${body%$'\n'*}"

  printf '%s' "$body" | jq -S "$strip_filter" > "$out" 2>/dev/null \
    || printf '%s' "$body" > "$out"   # non-JSON: dump raw so the diff still shows it

  printf '%-24s status=%s bytes=%s\n' "$name" "$status" "$(wc -c < "$out" | tr -d ' ')"
done
