#!/usr/bin/env bash
# Pokebuddy SessionStart hook
# Reads state, checks pokeget, displays sprite, injects session context.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE_BIN="node \"${PLUGIN_ROOT}/dist/state.js\""
SPRITE_BIN="node \"${PLUGIN_ROOT}/dist/sprites.js\""

# ---------------------------------------------------------------------------
# JSON escape helper — escapes a string for embedding in JSON
# ---------------------------------------------------------------------------
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"   # backslash
  s="${s//\"/\\\"}"   # double quote
  s="${s//$'\n'/\\n}" # newline
  s="${s//$'\r'/\\r}" # carriage return
  s="${s//$'\t'/\\t}" # tab
  echo "$s"
}

# ---------------------------------------------------------------------------
# Check if pokeget is installed
# ---------------------------------------------------------------------------
POKEGET_AVAILABLE=false
POKEGET_INSTALL_MSG=""
if command -v pokeget &>/dev/null; then
  POKEGET_AVAILABLE=true
else
  POKEGET_INSTALL_MSG=$(eval "$SPRITE_BIN --check" 2>/dev/null) || true
fi

# ---------------------------------------------------------------------------
# Read state
# ---------------------------------------------------------------------------
STATE=$(eval "$STATE_BIN read" 2>/dev/null) || STATE=""

if [ -z "$STATE" ]; then
  # No state — prompt user to run setup
  MSG="Pokebuddy is installed but not yet set up. Run /pokebuddy setup to choose your starter Pokémon!"
  printf '{"systemMessage":"%s"}' "$(json_escape "$MSG")"
  exit 0
fi

# Parse enabled flag
ENABLED=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('enabled',True)).lower())" 2>/dev/null || echo "true")
if [ "$ENABLED" = "false" ]; then
  exit 0
fi

# Parse active pokemon
SPECIES=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); p=d['party'][d['activeSlot']]; print(p['species'])" 2>/dev/null || echo "")
NICKNAME=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); p=d['party'][d['activeSlot']]; print(p['nickname'] or '')" 2>/dev/null || echo "")
LEVEL=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); p=d['party'][d['activeSlot']]; print(p['level'])" 2>/dev/null || echo "?")
NATURE=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); p=d['party'][d['activeSlot']]; print(p['nature'])" 2>/dev/null || echo "")
SHOW_SPRITE=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d['settings'].get('showSpriteOnSession',True)).lower())" 2>/dev/null || echo "true")

if [ -z "$SPECIES" ]; then
  exit 0
fi

# Determine display name
if [ -n "$NICKNAME" ]; then
  DISPLAY_NAME="$NICKNAME the $SPECIES"
else
  DISPLAY_NAME="$SPECIES"
fi

# Build context message
CONTEXT_LINES=()
CONTEXT_LINES+=("Your Pokémon companion is ready!")

if [ "$POKEGET_AVAILABLE" = false ] && [ -n "$POKEGET_INSTALL_MSG" ]; then
  CONTEXT_LINES+=("⚠️  Sprites unavailable — $POKEGET_INSTALL_MSG")
fi

# Render sprite if enabled and pokeget is available
if [ "$SHOW_SPRITE" = "true" ] && [ "$POKEGET_AVAILABLE" = "true" ]; then
  SPRITE=$(eval "$SPRITE_BIN \"$SPECIES\"" 2>/dev/null) || SPRITE=""
  if [ -n "$SPRITE" ]; then
    CONTEXT_LINES+=("$SPRITE")
  fi
fi

CONTEXT_LINES+=("▶ $DISPLAY_NAME (Level $LEVEL | $NATURE)")
CONTEXT_LINES+=("Use /pokebuddy show for stats, /pokebuddy party for your team.")

# Join lines
CONTEXT=$(printf '%s\n' "${CONTEXT_LINES[@]}")

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$(json_escape "$CONTEXT")"
exit 0
