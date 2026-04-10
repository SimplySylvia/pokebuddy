---
name: companion
description: >
  This skill handles all /pokebuddy commands: setup, show, stats, party, switch,
  mute, unmute, off, cancel-evolution, and settings. Use it whenever the user invokes
  /pokebuddy or any pokebuddy subcommand. Manages Pokémon companion state, sprite
  display, XP tracking, evolution, and quip configuration.
argument-hint: "[setup|show|stats|party|switch|mute|unmute|off|cancel-evolution|settings]"
---

# Pokebuddy Skill

You are handling a `/pokebuddy` command. Follow the instructions for the specific subcommand below.

**Important:** All state operations use the bash CLI at `${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh`. All sprite rendering uses `pokeget` directly. Always use `bash` to call state-cli.sh from the Bash tool. Sprites render in the Bash tool's terminal output — never paste ANSI/sprite output into your text response.

---

## /pokebuddy setup

First-time setup flow. Creates the initial state and picks a starter Pokémon.

**Step 0 — Check pokeget installation:**
```bash
command -v pokeget && echo "ok" || echo "pokeget not installed. Install with: brew install talwat/tap/pokeget  OR  cargo install pokeget"
```
- If it prints `ok`: proceed normally.
- If it prints the install message: display it to the user verbatim, then say:

  > "Pokebuddy works in text-only mode without pokeget — you'll see names instead of sprites. You can install it now and rerun `/pokebuddy setup`, or continue and install it later."

  Ask: "Continue without sprites, or install pokeget first?"
  - If "install first": stop here and let the user install.
  - If "continue": proceed — all sprite steps below will fall back to showing the Pokémon name in brackets (e.g., `[charmander]`).

**Step 1 — Check existing state:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" read
```
If state already exists with a party, tell the user: "You already have a Pokémon companion! Run `/pokebuddy show` to see them, or tell me 'reset' if you want to start over."

If the user confirms reset, proceed with the setup flow below.

**Step 2 — Present mode choice:**
Ask the user: "How would you like to receive your first Pokémon companion?"
1. **Choose a starter** — Browse and pick from 3 random Pokémon
2. **Mystery egg** — Receive a surprise egg that hatches after 25 prompts

**Step 3a — Starter selection flow:**

Run this to get 3 random starters with natures and shiny rolls:
```bash
python3 - "${CLAUDE_PLUGIN_ROOT}/data/pokemon-data.json" << 'EOF'
import sys, json, random
with open(sys.argv[1]) as f:
    d = json.load(f)
sample = random.sample(d["firstStagePokemon"], 3)
result = [{**p, "nature": random.choice(d["natures"]), "shiny": random.random() < 1/20} for p in sample]
print(json.dumps(result, indent=2))
EOF
```

Render all three sprites in a **single Bash call** so they appear together in one output window. Using the data from the JSON above (call the entries `a`, `b`, `c`), construct one chained command:

```bash
printf "── Option 1: [✨ if a.shiny][a.species] (#[a.pokedexId]) | [a.nature.name] nature ──\n" > /dev/tty && pokeget [a.pokedexId] --hide-name [--shiny if a.shiny] > /dev/tty && printf "\n── Option 2: [✨ if b.shiny][b.species] (#[b.pokedexId]) | [b.nature.name] nature ──\n" > /dev/tty && pokeget [b.pokedexId] --hide-name [--shiny if b.shiny] > /dev/tty && printf "\n── Option 3: [✨ if c.shiny][c.species] (#[c.pokedexId]) | [c.nature.name] nature ──\n" > /dev/tty && pokeget [c.pokedexId] --hide-name [--shiny if c.shiny] > /dev/tty
```

Label rules:
- Always include `| [x.nature.name] nature` after the Pokédex ID (where `x` is `a`, `b`, or `c`)
- If `x.shiny` is true: prefix name with `✨ ` and append `--shiny` to the sprite call
- If `x.shiny` is false: no prefix, no `--shiny` flag
- Square-bracket placeholders like `[✨ if x.shiny]` and `[--shiny if x.shiny]` are conditional: include the contents when the condition is true, include nothing (not even a space) when false

**Critical rendering rule:** All sprite calls use `> /dev/tty` to write directly to the terminal, bypassing Claude Code's collapsible tool output panel. Never paste raw ANSI into your text response.

Ask: "Which Pokémon will you choose? (1, 2, or 3)"

**Step 4 — Nickname:**
After the user picks, ask: "Give your Pokémon a nickname? (Press Enter to skip)"

**Step 5 — Assign nature and generate personality:**
Use the nature pre-rolled for the chosen option: `a.nature` for Option 1, `b.nature` for Option 2, `c.nature` for Option 3 (from the JSON array parsed in Step 3a). No additional roll is needed.

Then generate a short personality description (1-2 sentences) yourself, informed by:
- The Pokémon's species (their personality in the games, their type, their lore)
- The assigned nature and its `personalityDescription`

Example for a Jolly Charmander: *"A cheerful fire lizard who celebrates every successful build with a delighted tail-flare. Optimistic to a fault, Ember genuinely believes every bug is just a hidden feature."*

**Step 6 — Initialize state:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" init <species> <pokedexId> <nature> "<nickname or empty>"
```
If the chosen option was shiny (i.e. `a.shiny`, `b.shiny`, or `c.shiny` was true for the chosen option), also run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" set-flag party.0.shiny true
```
Then store the personality:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" set-personality "<personality description>"
```

**Step 7 — Wire up the status line:**

The SessionStart, UserPromptSubmit, and Stop hooks are auto-registered by the plugin system.
Only the `statusLine` needs to be configured manually in `~/.claude/settings.json`:
```bash
python3 - "${HOME}/.claude/settings.json" "${CLAUDE_PLUGIN_ROOT}" << 'EOF'
import sys, json

settings_path, plugin_root = sys.argv[1], sys.argv[2]
try:
    with open(settings_path) as f:
        settings = json.load(f)
except Exception:
    settings = {}

# Status line — sprite + stats bar after every response
settings["statusLine"] = {
    "type": "command",
    "command": f'bash "{plugin_root}/hooks/statusline.sh"'
}

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
print("Pokebuddy configured: status line registered.")
EOF
```

Tell the user: "Your Pokémon will now appear in the status bar at the bottom of your terminal. XP updates after every response, and they'll chime in occasionally between your prompts."

**Step 8 — Confirm:**
Display the Pokémon's sprite one more time (`> /dev/tty` for direct terminal output) and say:
> "Meet [Name]! [Personality description] They're ready to grow alongside your code. Every prompt earns XP — reach level 16 for your first evolution!"

**Step 3b — Egg flow (if user chose mystery egg):**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" init egg 0 <random_nature>
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" set-flag party.0.hatchAt 25
```
Tell the user: "You received a mysterious egg! It will hatch in 25 prompts. What could be inside...?"

---

## /pokebuddy show

Display the active Pokémon with basic stats.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" read
```

Render the sprite (write to /dev/tty so it appears directly in the terminal, not in a collapsible tool output panel):
```bash
pokeget <species> > /dev/tty   # add --shiny if shiny=true
```

Display below the sprite:
```
✨ [Name] the [species]   (✨ prefix only if shiny)
Level [X] | [Nature] nature
XP: [current] / [next_level_xp]  [████████░░] [X]%
Next evolution: [evolved_species] at level [Y]    (omit if no evolution)
```

Build the XP progress bar: 10 characters wide, filled with `█`, empty with `░`.

If the Pokémon is an egg, show: "🥚 Mystery Egg — hatches in [hatchAt] more prompts!"

---

## /pokebuddy stats

Full stat card for the active Pokémon.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" read
```

Display:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [Name] [✨ if shiny]
  Species:    [species] (#[pokedexId])
  Nickname:   [nickname or "—"]
  Nature:     [nature]
  Level:      [level]
  XP:         [xp] cumulative
  Evo. Stage: [evolutionStage] / [max based on chain]
  Caught:     [caughtAt date, formatted]
  
  "[personality]"
  
  Evolution:  [evolvedSpecies] at Lv.[evoLevel]  (or "Fully evolved" / "Special evo")
  Pending:    [Yes/No for evolutionPending]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total XP earned: [state.totalXP]
Total prompts:   [state.totalPrompts]
```

---

## /pokebuddy party

Display all Pokémon in the party (up to 3).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" read
```

Render all party members in a **single Bash call** so they appear together in one uncollapsed output panel. Build one chained command for all occupied slots, for example with 2 Pokémon:

```bash
printf "▶ Slot 1 — [Name] (Level [X] | [Nature])\n" > /dev/tty && pokeget <species> [--shiny if shiny] > /dev/tty && printf "\n  Slot 2 — [Name] (Level [X] | [Nature])\n" > /dev/tty && pokeget <species> [--shiny if shiny] > /dev/tty
```

Rules:
- Use `▶` for the active slot, leading spaces for others
- If shiny: add ✨ to the name in the label
- If egg: replace the sprite call with `printf "🥚 Mystery Egg — hatches in [hatchAt] prompts\n"`

If party has fewer than 3 Pokémon, note: "[X]/3 slots filled"

---

## /pokebuddy switch <slot>

Change the active Pokémon.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" read
```

Validate `slot` is 1-3 and that a Pokémon exists in that slot.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" set-flag activeSlot <slot-1>
```
(activeSlot is 0-indexed, so slot 1 → 0, slot 2 → 1, slot 3 → 2)

Confirm: "Switched to [Name]! They're now your active companion."

---

## /pokebuddy mute

Silence periodic quips.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" set-flag settings.muteQuips true
```

Confirm: "[Name] will stay quiet for now. Run /pokebuddy unmute when you want to hear from them again."

---

## /pokebuddy unmute

Re-enable periodic quips.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" set-flag settings.muteQuips false
```

Confirm: "[Name] is back! They'll chime in occasionally as you work."

---

## /pokebuddy off

Hide Pokebuddy for the session.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" set-flag enabled false
```

Confirm: "Pokebuddy is resting. Your XP will resume next session. Use /pokebuddy show to wake them up."

---

## /pokebuddy cancel-evolution

Cancel a pending evolution (the "B button" mechanic).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" read
```

If `evolutionPending` is false, respond: "There's no pending evolution to cancel right now."

If true:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" clear-flag evolutionPending
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" set-flag evolutionCancelledUntil <currentLevel+1>
```

Confirm: "Got it! [Name] stopped evolving. They'll have another chance at level [currentLevel+1]."

---

## /pokebuddy settings

View and adjust settings.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" read
```

Display current settings:
```
Pokebuddy Settings
──────────────────
Quip frequency:    [quipFrequency * 100]%  (chance per prompt)
Mute quips:        [Yes/No]
Show sprite on session start: [Yes/No]
```

If the user specifies a change in natural language, interpret it and apply:
- "set quip frequency to 10%" → `set-flag settings.quipFrequency 0.1`
- "mute quips" → `set-flag settings.muteQuips true`
- "disable sprite on startup" → `set-flag settings.showSpriteOnSession false`

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" set-flag <key> <value>
```

Confirm the change.

---

## Error handling

If `bash "${CLAUDE_PLUGIN_ROOT}/lib/state-cli.sh" read` fails (exits non-zero, prints "NO_STATE" to stderr):
→ Prompt the user to run `/pokebuddy setup` first.

If `pokeget` is not available:
→ Skip sprite rendering, show a text-only fallback with just the Pokémon name.
→ Optionally mention: "Install `pokeget` for sprite rendering: `brew install talwat/tap/pokeget` or `cargo install pokeget`"
