#!/usr/bin/env bash
# lib/state.sh — sourceable bash library for pokebuddy state operations
# Source this file from hooks; do not execute directly.
# Dependencies: python3 (for JSON), CLAUDE_PLUGIN_ROOT env var

# ---------------------------------------------------------------------------
# State file path
# ---------------------------------------------------------------------------

pb_state_path() {
  # Claude Code sets CLAUDE_PLUGIN_DATA when running hooks (points to
  # ~/.claude/plugins/data/pokebuddy-pokebuddy-marketplace/).
  # When called from the Bash tool (skill commands), CLAUDE_PLUGIN_DATA is not
  # set — use the same directory so both contexts share one state file.
  echo "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/pokebuddy-pokebuddy-marketplace}/pokebuddy-state.json"
}

# ---------------------------------------------------------------------------
# Read state — prints JSON to stdout, exits 1 if not found
# ---------------------------------------------------------------------------

pb_state_read() {
  local path
  path="$(pb_state_path)"
  if [[ ! -f "$path" ]]; then
    echo "NO_STATE" >&2
    return 1
  fi
  cat "$path"
}

# ---------------------------------------------------------------------------
# pb_award_xp <char_count>
# Awards XP, updates level, checks evolution, rolls for quip.
# ---------------------------------------------------------------------------

pb_award_xp() {
  local char_count="${1:-0}"
  local state_path
  state_path="$(pb_state_path)"
  local plugin_root="${CLAUDE_PLUGIN_ROOT:-}"

  [[ ! -f "$state_path" ]] && return 1

  python3 - "$char_count" "$state_path" "$plugin_root" << 'PYEOF'
import sys, json, math, random, os

char_count = int(sys.argv[1])
state_path = sys.argv[2]
plugin_root = sys.argv[3]

with open(state_path) as f:
    state = json.load(f)

if not state.get("enabled", True):
    sys.exit(0)

slot = state.get("activeSlot", 0)
pokemon = state["party"][slot]

# --- Egg hatching ---
if pokemon.get("hatchAt") is not None and pokemon["hatchAt"] > 0:
    pokemon["hatchAt"] -= 1
    state["totalPrompts"] = state.get("totalPrompts", 0) + 1
    tmp = state_path + ".tmp." + str(os.getpid())
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, state_path)
    sys.exit(0)

# --- XP award ---
xp_earned = max(1, math.floor(char_count / 100))
prev_level = pokemon.get("level", 5)

pokemon["xp"] = pokemon.get("xp", 0) + xp_earned
state["totalXP"] = state.get("totalXP", 0) + xp_earned
state["totalPrompts"] = state.get("totalPrompts", 0) + 1

# --- Level via segment interpolation (matches TS buildXpTable exactly) ---
milestones = [(5,0),(10,100),(16,250),(20,400),(32,900),(36,1100),(50,2500),(100,10000)]
total_xp = pokemon["xp"]
new_level = 5
for i in range(len(milestones) - 1):
    l0, x0 = milestones[i]
    l1, x1 = milestones[i + 1]
    if total_xp >= x1:
        new_level = l1
    elif total_xp >= x0:
        t = (total_xp - x0) / (x1 - x0)
        new_level = math.floor(l0 + t * (l1 - l0))
        break

pokemon["level"] = new_level

# --- Evolution check ---
if new_level > prev_level and not state.get("evolutionPending", False):
    data_path = os.path.join(plugin_root, "data", "pokemon-data.json") if plugin_root else ""
    if data_path and os.path.isfile(data_path):
        try:
            with open(data_path) as df:
                pdata = json.load(df)
            chains = pdata.get("evolutionChains", {})
            species = pokemon.get("species", "")
            chain = chains.get(species.lower())
            if chain and chain.get("evolvesAt", 0) > 0:
                evo_level = chain["evolvesAt"]
                cancelled_until = state.get("evolutionCancelledUntil") or 0
                if new_level >= evo_level and new_level > cancelled_until:
                    state["evolutionPending"] = True
        except Exception:
            pass

# --- Quip roll ---
settings = state.get("settings", {})
if not settings.get("muteQuips", False):
    freq = settings.get("quipFrequency", 0.15)
    if random.random() < freq:
        state["quipTriggered"] = True

# --- Atomic write ---
tmp = state_path + ".tmp." + str(os.getpid())
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(tmp, state_path)
PYEOF
}

# ---------------------------------------------------------------------------
# pb_apply_evolution
# Applies a pending evolution: updates species, increments evolutionStage,
# clears evolutionPending, resets evolutionCancelledUntil.
# ---------------------------------------------------------------------------

pb_apply_evolution() {
  local state_path
  state_path="$(pb_state_path)"
  local data_path="${CLAUDE_PLUGIN_ROOT:-}/data/pokemon-data.json"

  [[ ! -f "$state_path" ]] && return 1

  python3 - "$state_path" "$data_path" << 'PYEOF'
import sys, json, os

state_path = sys.argv[1]
data_path = sys.argv[2]

with open(state_path) as f:
    state = json.load(f)

slot = state.get("activeSlot", 0)
pokemon = state["party"][slot]

if os.path.isfile(data_path):
    with open(data_path) as f:
        pdata = json.load(f)
    chains = pdata.get("evolutionChains", {})
    chain = chains.get(pokemon["species"].lower())
    if chain:
        pokemon["species"] = chain["evolvesInto"]
        pokemon["evolutionStage"] = pokemon.get("evolutionStage", 1) + 1
        state["evolutionCancelledUntil"] = None

state["evolutionPending"] = False

tmp = state_path + ".tmp." + str(os.getpid())
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(tmp, state_path)
print(json.dumps(state, indent=2))
PYEOF
}

# ---------------------------------------------------------------------------
# pb_set_flag <dotted.path> <value>
# Sets a nested field. Coerces "true"/"false" to bool, numeric strings to
# numbers. Supports array indices (e.g. "party.0.shiny").
# ---------------------------------------------------------------------------

pb_set_flag() {
  local dotpath="$1"
  local value="$2"
  local state_path
  state_path="$(pb_state_path)"

  [[ ! -f "$state_path" ]] && return 1

  python3 - "$state_path" "$dotpath" "$value" << 'PYEOF'
import sys, json, os

state_path, dotpath, value = sys.argv[1], sys.argv[2], sys.argv[3]

with open(state_path) as f:
    state = json.load(f)

parts = dotpath.split(".")
obj = state
for key in parts[:-1]:
    try:
        obj = obj[int(key)]
    except (ValueError, TypeError):
        obj = obj[key]

last = parts[-1]

# Coerce value type (matching TypeScript setFlag behaviour)
if value == "true":
    coerced = True
elif value == "false":
    coerced = False
else:
    try:
        coerced = int(value)
    except ValueError:
        try:
            coerced = float(value)
        except ValueError:
            coerced = value

try:
    obj[int(last)] = coerced
except (ValueError, TypeError):
    obj[last] = coerced

tmp = state_path + ".tmp." + str(os.getpid())
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(tmp, state_path)
PYEOF
}

# ---------------------------------------------------------------------------
# pb_clear_flag <dotted.path>
# Sets a boolean field to false.
# ---------------------------------------------------------------------------

pb_clear_flag() {
  pb_set_flag "$1" "false"
}

# ---------------------------------------------------------------------------
# pb_init <species> <pokedex_id> <nature> [nickname]
# Creates initial state from scratch and writes it to disk.
# Prints the new state JSON to stdout.
# ---------------------------------------------------------------------------

pb_init() {
  local species="$1"
  local pokedex_id="$2"
  local nature="$3"
  local nickname="${4:-}"
  local state_path
  state_path="$(pb_state_path)"

  mkdir -p "$(dirname "$state_path")"

  python3 - "$state_path" "$species" "$pokedex_id" "$nature" "$nickname" << 'PYEOF'
import sys, json, os
from datetime import datetime, timezone

state_path, species, pokedex_id, nature, nickname = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
pokedex_id = int(pokedex_id)
nickname = nickname if nickname else None
is_egg = (species == "egg")

pokemon = {
    "species": species,
    "pokedexId": pokedex_id,
    "nickname": nickname,
    "nature": nature,
    "level": 5,
    "xp": 0,
    "shiny": False,
    "evolutionStage": 1,
    "caughtAt": datetime.now(timezone.utc).isoformat(),
    "personality": "",
    "hatchAt": 25 if is_egg else None,
}

state = {
    "version": 1,
    "enabled": True,
    "activeSlot": 0,
    "totalPrompts": 0,
    "totalXP": 0,
    "shinyCharm": False,
    "evolutionPending": False,
    "evolutionCancelledUntil": None,
    "quipTriggered": False,
    "inventory": {"pokeball": 0, "greatball": 0, "ultraball": 0, "masterball": 0},
    "party": [pokemon],
    "pokedex": [] if is_egg else [pokedex_id],
    "settings": {
        "quipFrequency": 0.15,
        "muteQuips": False,
        "showSpriteOnSession": True,
    },
}

tmp = state_path + ".tmp." + str(os.getpid())
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(tmp, state_path)
print(json.dumps(state, indent=2))
PYEOF
}

# ---------------------------------------------------------------------------
# pb_set_personality <text>
# Sets party[activeSlot].personality to the given text.
# ---------------------------------------------------------------------------

pb_set_personality() {
  local text="$1"
  local state_path
  state_path="$(pb_state_path)"

  [[ ! -f "$state_path" ]] && return 1

  python3 - "$state_path" "$text" << 'PYEOF'
import sys, json, os

state_path = sys.argv[1]
text = sys.argv[2]

with open(state_path) as f:
    state = json.load(f)

slot = state.get("activeSlot", 0)
if state["party"] and len(state["party"]) > slot:
    state["party"][slot]["personality"] = text

tmp = state_path + ".tmp." + str(os.getpid())
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(tmp, state_path)
PYEOF
}
