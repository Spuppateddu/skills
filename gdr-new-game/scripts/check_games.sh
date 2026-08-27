#!/usr/bin/env bash
# Show every game slug gdr-companion knows and where each one is wired.
#
# Usage:  check_games.sh [repo-root]        # default: current directory
#
# Exits 1 when a slug has config rows but no GameSeeder entry — that game loses
# its whole config on a fresh database, silently. Everything else is reported
# but does not fail: a game with no constants folder and no panels folder is
# perfectly normal (it uses the generic default tabs).
set -eu

ROOT="${1:-$PWD}"
BACKEND="$ROOT/gdr-companion-backend"
FRONTEND="$ROOT/gdr-companion-frontend"
SEEDER="$BACKEND/database/seeders/GameSeeder.php"
CONFIG="$BACKEND/database/seeders/data/character-config.json"

if [ ! -f "$SEEDER" ] || [ ! -f "$CONFIG" ]; then
    echo "Not a gdr-companion checkout: $ROOT" >&2
    echo "Expected $SEEDER and $CONFIG" >&2
    exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Slugs declared in GameSeeder.php
grep -o "'slug' => '[a-z0-9_]*'" "$SEEDER" \
    | sed "s/.*=> '//; s/'//" | sort -u > "$tmp/seeder"

# Slugs referenced by character-config.json
if command -v jq >/dev/null 2>&1; then
    jq -r '[.[][]?.game_slug] | .[]' "$CONFIG" 2>/dev/null | grep -v '^null$' | sort -u > "$tmp/config"
else
    grep -o '"game_slug"[[:space:]]*:[[:space:]]*"[a-z0-9_]*"' "$CONFIG" \
        | sed 's/.*"\([a-z0-9_]*\)"$/\1/' | sort -u > "$tmp/config"
fi

# Frontend folders
ls "$FRONTEND/constants" 2>/dev/null | grep -v '^app$' | sort -u > "$tmp/constants" || : > "$tmp/constants"
ls "$FRONTEND/components/character/panels" 2>/dev/null \
    | grep -v '^Shared$' | grep -v '^default$' | sort -u > "$tmp/panels" || : > "$tmp/panels"

cat "$tmp/seeder" "$tmp/config" "$tmp/constants" "$tmp/panels" | sort -u > "$tmp/all"

printf '%-22s %-8s %-8s %-11s %s\n' SLUG SEEDER CONFIG CONSTANTS PANELS
printf '%-22s %-8s %-8s %-11s %s\n' ---------------------- -------- -------- ----------- ------
while read -r slug; do
    [ -n "$slug" ] || continue
    s='-'; c='-'; k='-'; p='-'
    grep -qx "$slug" "$tmp/seeder"    && s='yes'
    grep -qx "$slug" "$tmp/config"    && c='yes'
    grep -qx "$slug" "$tmp/constants" && k='yes'
    grep -qx "$slug" "$tmp/panels"    && p='yes'
    printf '%-22s %-8s %-8s %-11s %s\n' "$slug" "$s" "$c" "$k" "$p"
done < "$tmp/all"

echo "Note: a panels/ folder name need not match a slug (panels/dnd serves dnd5e and dnd55e),"
echo "and a game with no constants/ and no panels/ folder simply uses the generic default tabs."
echo
# A hyphen in a slug breaks the panel-field slug parser in CharacterSheet.tsx.
if grep -q -- '-' "$tmp/all"; then
    echo "WARNING: a game slug contains a hyphen. Slugs must use underscores only."
fi

orphans="$(comm -13 "$tmp/seeder" "$tmp/config")"
if [ -n "$orphans" ]; then
    echo "BROKEN: these slugs have rows in character-config.json but no entry in GameSeeder.php."
    echo "CharacterConfigSeeder skips them without a word, so a fresh database loses their config:"
    echo "$orphans" | sed 's/^/  - /'
    echo
    echo "Add them to GameSeeder.php — the plan template's tasks T1.3 and T1.4 cover this."
    exit 1
fi

echo "OK: every slug in character-config.json has a GameSeeder entry."
