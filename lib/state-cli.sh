#!/usr/bin/env bash
# lib/state-cli.sh — CLI wrapper matching the old dist/state.js interface.
# Usage: state-cli.sh <command> [args...]
# Commands: read | init | award-xp | set-flag | clear-flag | update-evolution | set-personality
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# Ensure CLAUDE_PLUGIN_DATA is set to the canonical data directory.
# Claude Code sets this automatically in hook contexts but NOT in bash tool contexts
# (e.g. when the setup skill calls this script). Default to the known plugin data dir.
export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/pokebuddy-pokebuddy-marketplace}"

# shellcheck source=lib/state.sh
source "${PLUGIN_ROOT}/lib/state.sh"

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  read)
    pb_state_read
    ;;
  init)
    SPECIES="${1:-}"
    POKEDEX_ID="${2:-}"
    NATURE="${3:-}"
    NICKNAME="${4:-}"
    if [[ -z "$SPECIES" || -z "$POKEDEX_ID" || -z "$NATURE" ]]; then
      echo "Usage: state-cli.sh init <species> <pokedexId> <nature> [nickname]" >&2
      exit 1
    fi
    pb_init "$SPECIES" "$POKEDEX_ID" "$NATURE" "$NICKNAME"
    ;;
  award-xp)
    CHAR_COUNT="${1:-}"
    if [[ -z "$CHAR_COUNT" ]]; then
      echo "Usage: state-cli.sh award-xp <charCount>" >&2
      exit 1
    fi
    pb_award_xp "$CHAR_COUNT"
    ;;
  set-flag)
    FLAG="${1:-}"
    VALUE="${2:-}"
    if [[ -z "$FLAG" || -z "$VALUE" ]]; then
      echo "Usage: state-cli.sh set-flag <flag> <value>" >&2
      exit 1
    fi
    pb_set_flag "$FLAG" "$VALUE"
    ;;
  clear-flag)
    FLAG="${1:-}"
    if [[ -z "$FLAG" ]]; then
      echo "Usage: state-cli.sh clear-flag <flag>" >&2
      exit 1
    fi
    pb_clear_flag "$FLAG"
    ;;
  update-evolution)
    pb_apply_evolution
    ;;
  set-personality)
    TEXT="${*}"
    if [[ -z "$TEXT" ]]; then
      echo "Usage: state-cli.sh set-personality <text>" >&2
      exit 1
    fi
    pb_set_personality "$TEXT"
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Valid commands: read init award-xp set-flag clear-flag update-evolution set-personality" >&2
    exit 1
    ;;
esac
