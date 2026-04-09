#!/usr/bin/env bash
# Pokebuddy status line — shows companion name, level, and XP progress.
# Configured via settings.json statusLine.command.
# Runs locally after each assistant message (no token cost).

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/pokebuddy}"
STATE_FILE="${STATE_DIR}/pokebuddy-state.json"

# ANSI color codes
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
WHITE="\033[37m"
BRIGHT_YELLOW="\033[93m"
BRIGHT_CYAN="\033[96m"
BRIGHT_WHITE="\033[97m"

if [ ! -f "$STATE_FILE" ]; then
  # No state — show a prompt to get started
  printf "${DIM}  ○ No Pokémon companion yet — run /pokebuddy setup${RESET}\n"
  exit 0
fi

# Parse state with python3 (available everywhere on macOS/Linux)
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

    # Compute next level XP from the table baked into the state logic
    # Milestones: 5->0, 10->100, 16->250, 20->400, 32->900, 36->1100, 50->2500, 100->10000
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

# Determine display name
if [ -n "$NICKNAME" ] && [ "$NICKNAME" != "''" ]; then
  # Strip surrounding quotes from python repr output
  CLEAN_NICK="${NICKNAME//\'/}"
  DISPLAY_NAME="${CLEAN_NICK}"
else
  # Capitalize species name
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
if [ "$SHINY" = "true" ]; then
  SHINY_MARK="✨ "
fi

# Mute indicator
MUTE_MARK=""
if [ "$MUTE_QUIPS" = "true" ]; then
  MUTE_MARK=" ${DIM}(muted)${RESET}"
fi

# Species type color (rough approximation by name for common types)
case "$SPECIES" in
  charmander|charmeleon|charizard|cyndaquil|quilava|typhlosion|torchic|combusken|blaziken|chimchar|monferno|infernape|litten|torracat|incineroar|scorbunny|raboot|cinderace)
    SPECIES_COLOR="${RED}" ;;
  squirtle|wartortle|blastoise|totodile|croconaw|feraligatr|mudkip|marshtomp|swampert|piplup|prinplup|empoleon|popplio|brionne|primarina|sobble|drizzile|inteleon)
    SPECIES_COLOR="${BRIGHT_CYAN}" ;;
  bulbasaur|ivysaur|venusaur|chikorita|bayleef|meganium|treecko|grovyle|sceptile|turtwig|grotle|torterra|snivy|servine|serperior|chespin|quilladin|chesnaught|rowlet|dartrix|grookey|thwackey)
    SPECIES_COLOR="\033[32m" ;; # green
  pikachu|raichu|jolteon|shinx|luxio|luxray|blitzle|zebstrika|scorbunny)
    SPECIES_COLOR="${BRIGHT_YELLOW}" ;;
  *)
    SPECIES_COLOR="${BRIGHT_WHITE}" ;;
esac

# Render the status line
printf "  ${SHINY_MARK}${BOLD}${SPECIES_COLOR}${DISPLAY_NAME}${RESET}  ${DIM}Lv${RESET}${BOLD}${WHITE}${LEVEL}${RESET}  ${BAR}  ${DIM}${XP} XP${RESET}${MUTE_MARK}\n"
