#!/usr/bin/env bash
# Pokebuddy Stop hook
# Handles two events (in priority order):
#   1. Evolution pending → render sprites to terminal, inject plain-text narrative via "block"
#   2. Quip triggered   → build quip prompt, inject via "block" (Claude generates the quip)
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# shellcheck source=../lib/state.sh
source "${PLUGIN_ROOT}/lib/state.sh"

DATA_FILE="${PLUGIN_ROOT}/data/pokemon-data.json"

# ---------------------------------------------------------------------------
# Read stdin (contains session_id, transcript_path, reason)
# ---------------------------------------------------------------------------
INPUT=$(cat)

# ---------------------------------------------------------------------------
# Read state
# ---------------------------------------------------------------------------
STATE=$(pb_state_read 2>/dev/null) || exit 0

# Parse fields
parse_field() {
  echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null || echo ""
}

ENABLED=$(parse_field "str(d.get('enabled',True)).lower()")
if [[ "$ENABLED" = "false" ]]; then
  exit 0
fi

MUTE_QUIPS=$(parse_field "str(d['settings'].get('muteQuips',False)).lower()")
EVOLUTION_PENDING=$(parse_field "str(d.get('evolutionPending',False)).lower()")
QUIP_TRIGGERED=$(parse_field "str(d.get('quipTriggered',False)).lower()")

SPECIES=$(parse_field "d['party'][d['activeSlot']]['species']")
NICKNAME=$(parse_field "d['party'][d['activeSlot']]['nickname'] or ''")
LEVEL=$(parse_field "d['party'][d['activeSlot']]['level']")
SHINY=$(parse_field "str(d['party'][d['activeSlot']].get('shiny',False)).lower()")

DISPLAY_NAME="${NICKNAME:-$SPECIES}"

# ---------------------------------------------------------------------------
# 1. Evolution sequence (higher priority)
# ---------------------------------------------------------------------------
if [[ "$EVOLUTION_PENDING" = "true" ]]; then
  EVOLVED_SPECIES=$(python3 - "$SPECIES" "$DATA_FILE" << 'PYEOF'
import sys, json
species, data_path = sys.argv[1], sys.argv[2]
with open(data_path) as f:
    d = json.load(f)
chain = d.get("evolutionChains", {}).get(species.lower())
print(chain["evolvesInto"] if chain else "")
PYEOF
  )

  if [[ -n "$EVOLVED_SPECIES" ]]; then
    # Render BEFORE sprite directly to terminal (/dev/tty bypasses collapsible panels)
    SHINY_FLAG=""
    [[ "$SHINY" = "true" ]] && SHINY_FLAG="--shiny"
    if command -v pokeget &>/dev/null; then
      pokeget "$SPECIES" --hide-name ${SHINY_FLAG:+"$SHINY_FLAG"} > /dev/tty 2>/dev/null || \
      pokeget "$SPECIES" --hide-name ${SHINY_FLAG:+"$SHINY_FLAG"} >&2 2>/dev/null || true
    fi

    # Apply evolution state change
    pb_apply_evolution > /dev/null

    # Render AFTER sprite directly to terminal
    if command -v pokeget &>/dev/null; then
      pokeget "$EVOLVED_SPECIES" --hide-name ${SHINY_FLAG:+"$SHINY_FLAG"} > /dev/tty 2>/dev/null || \
      pokeget "$EVOLVED_SPECIES" --hide-name ${SHINY_FLAG:+"$SHINY_FLAG"} >&2 2>/dev/null || true
    fi

    # Emit block decision — plain text only, json.dumps handles all escaping
    python3 -c "
import json, sys
dn, evo = sys.argv[1], sys.argv[2]
reason = f'What? {dn} is evolving!\n...\n...\nCongratulations! {dn} evolved into {evo}!'
print(json.dumps({'decision': 'block', 'reason': reason}))
" "$DISPLAY_NAME" "$EVOLVED_SPECIES"
    exit 0
  else
    # No evolved form — clear the pending flag
    pb_clear_flag "evolutionPending"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Quip generation
# ---------------------------------------------------------------------------
if [[ "$QUIP_TRIGGERED" = "true" && "$MUTE_QUIPS" != "true" ]]; then
  # Extract context from transcript (last user message)
  CONTEXT="their code"
  if command -v jq &>/dev/null; then
    TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
  else
    TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('transcript_path',''))" 2>/dev/null || echo "")
  fi

  if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
    RAW_CONTEXT=$(python3 -c "
import sys, json

path = sys.argv[1]
try:
    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]
except Exception:
    sys.exit(0)

def extract_text(content):
    '''Recursively extract plain text from content in any transcript format.'''
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, dict):
        # Unwrap nested message objects: {role, content} or {text}
        inner = content.get('content') or content.get('text') or ''
        return extract_text(inner)
    if isinstance(content, list):
        # Only keep type:text items; skip tool_result, tool_use, etc.
        parts = [c.get('text', '') for c in content
                 if isinstance(c, dict) and c.get('type') == 'text']
        return ' '.join(parts).strip()
    return ''

# Walk backwards through all lines looking for the last human/user turn with text
for line in reversed(lines):
    try:
        obj = json.loads(line)
        role = obj.get('role') or obj.get('type', '')
        if role in ('user', 'human'):
            raw = obj.get('content', '') or obj.get('message', '') or obj.get('text', '')
            text = extract_text(raw)
            if text and len(text) > 3:
                words = text.split()[:25]
                print(' '.join(words))
                break
    except Exception:
        pass
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "")
    if [[ -n "$RAW_CONTEXT" ]]; then
      CONTEXT="$RAW_CONTEXT"
    fi
  fi

  # Clear the flag BEFORE outputting block (prevents double-fire on recursive Stop call)
  pb_clear_flag "quipTriggered"

  # Build quip prompt inline (replaces quip.ts / buildQuipPrompt)
  # Re-reads state from disk so we see the cleared quipTriggered flag
  STATE_PATH="$(pb_state_path)"

  python3 - "$STATE_PATH" "$DATA_FILE" "$CONTEXT" "$DISPLAY_NAME" "$LEVEL" << 'PYEOF'
import sys, json, os

state_path, data_path, context, display_name, level = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

with open(state_path) as f:
    state = json.load(f)
with open(data_path) as f:
    pdata = json.load(f)

slot = state.get("activeSlot", 0)
pokemon = state["party"][slot]
nature_name = pokemon.get("nature", "")
species = pokemon.get("species", "")

# Prefer the rich custom personality written during setup; fall back to nature description
custom_personality = (pokemon.get("personality") or "").strip()
personality_adj = nature_name.lower() or "quiet"
for n in pdata.get("natures", []):
    if n["name"] == nature_name:
        personality_adj = n.get("personalityAdjective", nature_name.lower())
        if not custom_personality:
            custom_personality = n.get("personalityDescription", "")
        break

personality_line = custom_personality or f"a {nature_name} {species}"

quip_prompt = (
    f"You are {display_name}, a {nature_name} {species} at level {level}.\n"
    f"Your personality: {personality_line}\n"
    f"The developer just worked on: {context}.\n"
    f"Generate a short, in-character comment (1-2 sentences). "
    f"Stay in character. Be {personality_adj}.\n"
    f"Do not use the developer's name. Do not mention Claude or AI. "
    f"Keep it light and fun.\n"
    f"Respond with ONLY the quip \u2014 no prefixes, no explanations."
)

full_prompt = (
    f"[Pokebuddy quip \u2014 respond as {display_name} (Level {level}) "
    f"with exactly 1-2 sentences in character, then stop.]\n\n"
    f"{quip_prompt}"
)

print(json.dumps({"decision": "block", "reason": full_prompt}))
PYEOF
  exit 0
fi

# No action needed — allow stop
exit 0
