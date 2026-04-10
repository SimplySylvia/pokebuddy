#!/usr/bin/env bash
# Pokebuddy UserPromptSubmit hook (async: true)
# Awards XP for the prompt. Runs async so it won't block Claude's response.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# shellcheck source=../lib/state.sh
source "${PLUGIN_ROOT}/lib/state.sh"

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

# Award XP (handles quip roll and evolution check atomically)
pb_award_xp "$CHAR_COUNT" &>/dev/null || true

exit 0
