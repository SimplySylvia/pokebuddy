#!/usr/bin/env bash
# Pokebuddy UserPromptSubmit hook (async: true)
# Awards XP for the prompt and rolls for quip trigger.
# Must complete quickly — runs async so it won't block Claude's response.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE_BIN="node \"${PLUGIN_ROOT}/dist/state.js\""

# Read hook input from stdin
INPUT=$(cat)

# Extract prompt text — try jq first, fall back to python3
if command -v jq &>/dev/null; then
  PROMPT_TEXT=$(echo "$INPUT" | jq -r '.user_prompt // ""' 2>/dev/null || echo "")
else
  PROMPT_TEXT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('user_prompt',''))" 2>/dev/null || echo "")
fi

# Measure character count
CHAR_COUNT=${#PROMPT_TEXT}

# Award XP (this also handles quip roll and evolution check atomically)
eval "$STATE_BIN award-xp \"$CHAR_COUNT\"" &>/dev/null || true

# UserPromptSubmit hook outputs nothing — we don't need to inject content here
exit 0
