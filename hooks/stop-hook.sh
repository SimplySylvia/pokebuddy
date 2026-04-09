#!/usr/bin/env bash
# Pokebuddy Stop hook
# Handles two events (in priority order):
#   1. Evolution pending → render evolution sequence, inject via "block"
#   2. Quip triggered   → build quip prompt, inject via "block" (Claude generates the quip)
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE_BIN="node \"${PLUGIN_ROOT}/dist/state.js\""
SPRITE_BIN="node \"${PLUGIN_ROOT}/dist/sprites.js\""
QUIP_BIN="node \"${PLUGIN_ROOT}/dist/quip.js\""

# ---------------------------------------------------------------------------
# JSON escape helper
# ---------------------------------------------------------------------------
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

# ---------------------------------------------------------------------------
# Read stdin (contains session_id, transcript_path, reason)
# ---------------------------------------------------------------------------
INPUT=$(cat)

# ---------------------------------------------------------------------------
# Read state
# ---------------------------------------------------------------------------
STATE=$(eval "$STATE_BIN read" 2>/dev/null) || { exit 0; }

# Parse fields via python3 (available on macOS without extra deps)
parse_field() {
  echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null || echo ""
}

ENABLED=$(parse_field "str(d.get('enabled',True)).lower()")
if [ "$ENABLED" = "false" ]; then
  exit 0
fi

MUTE_QUIPS=$(parse_field "str(d['settings'].get('muteQuips',False)).lower()")
EVOLUTION_PENDING=$(parse_field "str(d.get('evolutionPending',False)).lower()")
QUIP_TRIGGERED=$(parse_field "str(d.get('quipTriggered',False)).lower()")

SPECIES=$(parse_field "d['party'][d['activeSlot']]['species']")
NICKNAME=$(parse_field "d['party'][d['activeSlot']]['nickname'] or ''")
LEVEL=$(parse_field "d['party'][d['activeSlot']]['level']")

DISPLAY_NAME="${NICKNAME:-$SPECIES}"

# ---------------------------------------------------------------------------
# 1. Evolution sequence (higher priority)
# ---------------------------------------------------------------------------
if [ "$EVOLUTION_PENDING" = "true" ]; then
  # Get evolved species from pokemon-data
  EVOLVED_SPECIES=$(node -e "
    const { getEvolvedSpecies } = await import('${PLUGIN_ROOT}/dist/pokemon-data.js');
    process.stdout.write(getEvolvedSpecies('${SPECIES}') || '');
  " 2>/dev/null || echo "")

  if [ -n "$EVOLVED_SPECIES" ]; then
    # Render before sprite
    BEFORE_SPRITE=$(eval "$SPRITE_BIN \"$SPECIES\"" 2>/dev/null || echo "[$SPECIES]")
    # Update state to new species
    eval "$STATE_BIN update-evolution" &>/dev/null || true
    # Render after sprite
    AFTER_SPRITE=$(eval "$SPRITE_BIN \"$EVOLVED_SPECIES\"" 2>/dev/null || echo "[$EVOLVED_SPECIES]")

    EVOLUTION_TEXT=$(cat <<EOF
${BEFORE_SPRITE}

What? ${DISPLAY_NAME} is evolving!
...
...
Congratulations! ${DISPLAY_NAME} evolved into ${EVOLVED_SPECIES}!

${AFTER_SPRITE}
EOF
)

    printf '{"decision":"block","reason":"%s"}' "$(json_escape "$EVOLUTION_TEXT")"
    exit 0
  else
    # No evolved form found — clear the pending flag anyway
    eval "$STATE_BIN clear-flag evolutionPending" &>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# 2. Quip generation
# ---------------------------------------------------------------------------
if [ "$QUIP_TRIGGERED" = "true" ] && [ "$MUTE_QUIPS" != "true" ]; then
  # Extract context from transcript (last user message)
  CONTEXT="their code"
  if command -v jq &>/dev/null; then
    TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
  else
    TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('transcript_path',''))" 2>/dev/null || echo "")
  fi

  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Get last user message from JSONL transcript
    RAW_CONTEXT=$(tail -20 "$TRANSCRIPT_PATH" | python3 -c "
import sys, json
lines = [l.strip() for l in sys.stdin if l.strip()]
for line in reversed(lines):
    try:
        obj = json.loads(line)
        if obj.get('role') == 'user':
            content = obj.get('content', '')
            if isinstance(content, list):
                content = ' '.join(c.get('text','') for c in content if isinstance(c,dict))
            words = str(content).split()[:20]
            print(' '.join(words))
            break
    except Exception:
        pass
" 2>/dev/null || echo "")
    if [ -n "$RAW_CONTEXT" ]; then
      CONTEXT="$RAW_CONTEXT"
    fi
  fi

  # Encode state as base64 for quip.js
  STATE_B64=$(echo "$STATE" | base64)

  # Build quip prompt
  QUIP_PROMPT=$(eval "$QUIP_BIN \"$STATE_B64\" \"$CONTEXT\"" 2>/dev/null || echo "")

  # Clear the flag BEFORE outputting block (prevents double-fire on recursive Stop call)
  eval "$STATE_BIN clear-flag quipTriggered" &>/dev/null || true

  if [ -n "$QUIP_PROMPT" ]; then
    # Prefix the prompt so Claude knows to respond as the Pokémon and then stop
    FULL_PROMPT="[Pokebuddy quip — respond as ${DISPLAY_NAME} (Level ${LEVEL}) with exactly 1-2 sentences in character, then stop.]

${QUIP_PROMPT}"

    printf '{"decision":"block","reason":"%s"}' "$(json_escape "$FULL_PROMPT")"
    exit 0
  fi
fi

# No action needed — allow stop
exit 0
