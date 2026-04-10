#!/usr/bin/env bash
# Pokebuddy status line — sprite + stats panel rendered after every assistant message.
# Multi-line output is fully supported by Claude Code's statusLine feature.

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/pokebuddy-pokebuddy-marketplace}"
STATE_FILE="${STATE_DIR}/pokebuddy-state.json"

# ANSI color codes
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
RED="\033[31m"
YELLOW="\033[33m"
BRIGHT_YELLOW="\033[93m"
BRIGHT_CYAN="\033[96m"
BRIGHT_WHITE="\033[97m"

if [ ! -f "$STATE_FILE" ]; then
  printf "${DIM}  ○ No Pokémon companion yet — run /pokebuddy setup${RESET}\n"
  exit 0
fi

# Parse state with python3
read -r ENABLED SPECIES NICKNAME NATURE LEVEL XP NEXT_LEVEL_XP SHINY MUTE_QUIPS < <(python3 -c "
import json, sys
try:
    with open('${STATE_FILE}') as f:
        d = json.load(f)
    enabled = str(d.get('enabled', True)).lower()
    slot = d.get('activeSlot', 0)
    p = d['party'][slot]
    species = p['species']
    nickname = p.get('nickname') or ''
    nature = p.get('nature', '')
    level = p.get('level', 5)
    xp = p.get('xp', 0)
    mute = str(d['settings'].get('muteQuips', False)).lower()
    shiny = str(p.get('shiny', False)).lower()

    milestones = [(5,0),(10,100),(16,250),(20,400),(32,900),(36,1100),(50,2500),(100,10000)]
    next_xp = 10000
    for i in range(len(milestones)-1):
        l0, x0 = milestones[i]
        l1, x1 = milestones[i+1]
        if l0 <= level < l1:
            t = (level + 1 - l0) / (l1 - l0)
            next_xp = round(x0 + t * (x1 - x0))
            break
    print(enabled, species, repr(nickname), nature, level, xp, next_xp, shiny, mute)
except Exception as e:
    print('true', 'unknown', \"''\", '', 5, 0, 100, 'false', 'false')
" 2>/dev/null)

if [ "$ENABLED" = "false" ]; then
  printf "${DIM}  ○ Pokebuddy is resting${RESET}\n"
  exit 0
fi

# ---------------------------------------------------------------------------
# Sprite panel — cached to disk so every re-render uses identical bytes.
# Cache is keyed by species+shiny so it auto-invalidates on evolution/switch.
# ---------------------------------------------------------------------------
if command -v pokeget &>/dev/null; then
  if [ "$SPECIES" = "egg" ]; then
    printf '   ,-.\n  / \  \\\n |     |\n  \   /\n   `-'"'"'\n  [Egg]\n'
  else
    SHINY_FLAG=""
    [ "$SHINY" = "true" ] && SHINY_FLAG="--shiny"

    SPRITE_CACHE="${STATE_DIR}/sprite-${SPECIES}-${SHINY}.txt"
    if [ ! -s "$SPRITE_CACHE" ]; then
      # Force truecolor so the cached bytes match the display context
      COLORTERM=truecolor pokeget "$SPECIES" --hide-name ${SHINY_FLAG:+"$SHINY_FLAG"} \
        > "$SPRITE_CACHE" 2>/dev/null || rm -f "$SPRITE_CACHE"
    fi

    if [ -s "$SPRITE_CACHE" ]; then
      cat "$SPRITE_CACHE"
    fi
  fi
  printf "\033[0m"
fi

# ---------------------------------------------------------------------------
# Stats bar — name, level, XP progress
# ---------------------------------------------------------------------------

# Determine display name
if [ -n "$NICKNAME" ] && [ "$NICKNAME" != "''" ]; then
  CLEAN_NICK="${NICKNAME//\'/}"
  DISPLAY_NAME="${CLEAN_NICK}"
else
  DISPLAY_NAME="$(echo "${SPECIES:0:1}" | tr '[:lower:]' '[:upper:]')${SPECIES:1}"
fi

# Build XP progress bar (10 chars wide)
if [ "$NEXT_LEVEL_XP" -gt 0 ] 2>/dev/null; then
  FILLED=$(python3 -c "print(min(10, round(10 * ${XP} / ${NEXT_LEVEL_XP})))" 2>/dev/null || echo 5)
else
  FILLED=10
fi
EMPTY=$((10 - FILLED))
BAR="${BRIGHT_YELLOW}$(printf '█%.0s' $(seq 1 $FILLED 2>/dev/null))${DIM}$(printf '░%.0s' $(seq 1 $EMPTY 2>/dev/null))${RESET}"

# Shiny indicator
SHINY_MARK=""
[ "$SHINY" = "true" ] && SHINY_MARK="✨ "

# Mute indicator
MUTE_MARK=""
[ "$MUTE_QUIPS" = "true" ] && MUTE_MARK=" ${DIM}(muted)${RESET}"

# Species type color
case "$SPECIES" in
  charmander|charmeleon|charizard|cyndaquil|quilava|typhlosion|torchic|combusken|blaziken|chimchar|monferno|infernape|litten|torracat|incineroar|scorbunny|raboot|cinderace)
    SPECIES_COLOR="${RED}" ;;
  squirtle|wartortle|blastoise|totodile|croconaw|feraligatr|mudkip|marshtomp|swampert|piplup|prinplup|empoleon|popplio|brionne|primarina|sobble|drizzile|inteleon)
    SPECIES_COLOR="${BRIGHT_CYAN}" ;;
  bulbasaur|ivysaur|venusaur|chikorita|bayleef|meganium|treecko|grovyle|sceptile|turtwig|grotle|torterra|snivy|servine|serperior|chespin|quilladin|chesnaught|rowlet|dartrix|grookey|thwackey)
    SPECIES_COLOR="\033[32m" ;;
  pikachu|raichu|jolteon|shinx|luxio|luxray|blitzle|zebstrika)
    SPECIES_COLOR="${BRIGHT_YELLOW}" ;;
  *)
    SPECIES_COLOR="${BRIGHT_WHITE}" ;;
esac

printf "  ${SHINY_MARK}${BOLD}${SPECIES_COLOR}${DISPLAY_NAME}${RESET}  ${DIM}Lv${RESET}${BOLD}\033[37m${LEVEL}${RESET}  ${BAR}  ${DIM}${XP} XP${RESET}${MUTE_MARK}\n"

# Session greeting — extra line shown for 45s after session start.
# Written by session-start.sh; age-checked here; cleaned up when stale.
GREETING_FILE="${STATE_DIR}/session-greeting.txt"
if [ -f "$GREETING_FILE" ]; then
  file_age=$(( $(date +%s) - $(stat -f %m "$GREETING_FILE" 2>/dev/null || echo 0) ))
  if [ "$file_age" -lt 45 ] 2>/dev/null; then
    GREETING=$(cat "$GREETING_FILE" 2>/dev/null || echo "")
    if [ -n "$GREETING" ]; then
      printf "  ${BRIGHT_CYAN}${GREETING}${RESET}\n"
    fi
  else
    rm -f "$GREETING_FILE"
  fi
fi
