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
      # Run pokeget inside a Python-created PTY so isatty(stdout) returns true.
      # Without a real PTY, pokeget detects a pipe and swaps fg/bg on block chars.
      # COLUMNS=220 gives it a wide canvas for correct centering.
      python3 - "$SPECIES" "$SHINY" > "$SPRITE_CACHE" 2>/dev/null << 'PYEOF'
import sys, os, pty, termios, struct, fcntl, select

species, shiny = sys.argv[1], sys.argv[2] == 'true'
cmd = ['pokeget', species, '--hide-name'] + (['--shiny'] if shiny else [])

master_fd, slave_fd = pty.openpty()
try:
    fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 220, 0, 0))
except Exception:
    pass

pid = os.fork()
if pid == 0:
    os.close(master_fd)
    os.setsid()
    try:
        fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)
    except Exception:
        pass
    for fd in (0, 1, 2):
        os.dup2(slave_fd, fd)
    if slave_fd > 2:
        os.close(slave_fd)
    os.execvpe(cmd[0], cmd, {**os.environ, 'COLORTERM': 'truecolor'})
    os._exit(1)

os.close(slave_fd)
chunks = []
while True:
    try:
        r, _, _ = select.select([master_fd], [], [], 3.0)
        if not r:
            break
        data = os.read(master_fd, 4096)
        if not data:
            break
        chunks.append(data)
    except OSError:
        break
try:
    os.waitpid(pid, 0)
    os.close(master_fd)
except Exception:
    pass

out = b''.join(chunks).replace(b'\r\n', b'\n').replace(b'\r', b'\n')

# Normalize left margin: pokeget centering varies by TTY context.
# Find the minimum leading-space count across non-empty lines and
# pad every line so that the tightest row has at least 4 spaces.
lines = out.split(b'\n')
non_empty = [l for l in lines if l.strip()]
if non_empty:
    def _leading(l):
        return len(l) - len(l.lstrip(b' '))
    min_margin = min(_leading(l) for l in non_empty)
    if min_margin < 5:
        pad = b' ' * (5 - min_margin)
        lines = [pad + l if l.strip() else l for l in lines]
    out = b'\n'.join(lines)

sys.stdout.buffer.write(out)
PYEOF
      [ -s "$SPRITE_CACHE" ] || rm -f "$SPRITE_CACHE"
    fi

    if [ -s "$SPRITE_CACHE" ]; then
      printf "\033[0m"
      cat "$SPRITE_CACHE"
      printf "\033[0m"
    fi
  fi
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
