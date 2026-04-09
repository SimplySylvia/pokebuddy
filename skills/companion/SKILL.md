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

**Important:** All state operations use the compiled TypeScript CLI at `${CLAUDE_PLUGIN_ROOT}/dist/state.js`. All sprite rendering uses `${CLAUDE_PLUGIN_ROOT}/dist/sprites.js`. Always use `node` to call these directly from the Bash tool.

---

## /pokebuddy setup

First-time setup flow. Creates the initial state and picks a starter Pokémon.

**Step 0 — Check pokeget installation:**
```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" --check
```
- If it prints `ok`: proceed normally.
- If it exits non-zero: display the output to the user verbatim — it contains platform-specific install instructions. Then say:

  > "Pokebuddy works in text-only mode without pokeget — you'll see names instead of sprites. You can install it now and rerun `/pokebuddy setup`, or continue and install it later."

  Ask: "Continue without sprites, or install pokeget first?"
  - If "install first": stop here and let the user install.
  - If "continue": proceed — all sprite steps below will fall back to showing the Pokémon name in brackets (e.g., `[charmander]`).

**Step 1 — Check existing state:**
```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" read
```
If state already exists with a party, tell the user: "You already have a Pokémon companion! Run `/pokebuddy show` to see them, or tell me 'reset' if you want to start over."

If the user confirms reset, proceed with the setup flow below.

**Step 2 — Present mode choice:**
Ask the user: "How would you like to receive your first Pokémon companion?"
1. **Choose a starter** — Browse and pick from 3 random Pokémon
2. **Mystery egg** — Receive a surprise egg that hatches after 25 prompts

**Step 3a — Starter selection flow:**

Run this JavaScript to get 3 random starters:
```bash
node -e "
const { getThreeRandomStarters } = await import('${CLAUDE_PLUGIN_ROOT}/dist/pokemon-data.js');
const [a, b, c] = getThreeRandomStarters();
console.log(JSON.stringify([a, b, c]));
"
```

Render all three sprites in a **single Bash call** so they appear together in one output window. Using the IDs from `[a, b, c]`, construct one chained command:

```bash
printf "── Option 1: [a.name] (#[a.id]) ──\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" [a.id] --hide-name && printf "\n── Option 2: [b.name] (#[b.id]) ──\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" [b.id] --hide-name && printf "\n── Option 3: [c.name] (#[c.id]) ──\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" [c.id] --hide-name
```

**Critical rendering rule:** ANSI sprite output renders correctly in the Bash tool output panel — never paste raw ANSI into your text response. All three sprites **must** go in a single bash call so they appear together in one uncollapsed output panel.

Ask: "Which Pokémon will you choose? (1, 2, or 3)"

**Step 4 — Nickname:**
After the user picks, ask: "Give your Pokémon a nickname? (Press Enter to skip)"

**Step 5 — Assign nature and generate personality:**
Pick a random nature:
```bash
node -e "
const { getRandomNature } = await import('${CLAUDE_PLUGIN_ROOT}/dist/pokemon-data.js');
console.log(JSON.stringify(getRandomNature()));
"
```

Then generate a short personality description (1-2 sentences) yourself, informed by:
- The Pokémon's species (their personality in the games, their type, their lore)
- The assigned nature and its `personalityDescription`

Example for a Jolly Charmander: *"A cheerful fire lizard who celebrates every successful build with a delighted tail-flare. Optimistic to a fault, Ember genuinely believes every bug is just a hidden feature."*

**Step 6 — Initialize state:**
```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" init <species> <pokedexId> <nature> "<nickname or empty>"
```
Then store the personality:
```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" set-personality "<personality description>"
```

**Step 7 — Wire up the status line:**

Add Pokebuddy to the Claude Code status bar (the same location `/buddy` appears) by updating `~/.claude/settings.json`. Read the current settings first:
```bash
cat ~/.claude/settings.json 2>/dev/null || echo "{}"
```

Then merge in the `statusLine` key using the Bash tool. If `statusLine` doesn't exist yet, add it:
```bash
node -e "
const fs = require('fs');
const path = require('path');
const settingsPath = path.join(process.env.HOME, '.claude', 'settings.json');
const settings = fs.existsSync(settingsPath) ? JSON.parse(fs.readFileSync(settingsPath, 'utf8')) : {};
settings.statusLine = {
  type: 'command',
  command: 'bash \"${CLAUDE_PLUGIN_ROOT}/hooks/statusline.sh\"'
};
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
console.log('Status line configured.');
"
```

Tell the user: "Your Pokémon will now appear in the status bar at the bottom of your terminal — just like `/buddy`, but with XP tracking. You'll see their name, level, and progress bar update after every response."

If `settings.json` already has a `statusLine` entry from another source, show the user both values and ask which they'd like to keep, or whether to combine them (e.g., run both scripts in sequence).

**Step 8 — Confirm:**
Display the Pokémon's sprite one more time and say:
> "Meet [Name]! [Personality description] They're ready to grow alongside your code. Every prompt earns XP — reach level 16 for your first evolution!"

**Step 3b — Egg flow (if user chose mystery egg):**
```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" init egg 0 <random_nature>
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" set-flag party.0.hatchAt 25
```
Tell the user: "You received a mysterious egg! It will hatch in 25 prompts. What could be inside...?"

---

## /pokebuddy show

Display the active Pokémon with basic stats.

```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" read
```

Render the sprite:
```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" <species>   # add --shiny if shiny=true
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
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" read
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
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" read
```

Render all party members in a **single Bash call** so they appear together in one uncollapsed output panel. Build one chained command for all occupied slots, for example with 2 Pokémon:

```bash
printf "▶ Slot 1 — [Name] (Level [X] | [Nature])\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" <species> [--shiny if shiny] && printf "\n  Slot 2 — [Name] (Level [X] | [Nature])\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" <species> [--shiny if shiny]
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
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" read
```

Validate `slot` is 1-3 and that a Pokémon exists in that slot.

```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" set-flag activeSlot <slot-1>
```
(activeSlot is 0-indexed, so slot 1 → 0, slot 2 → 1, slot 3 → 2)

Confirm: "Switched to [Name]! They're now your active companion."

---

## /pokebuddy mute

Silence periodic quips.

```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" set-flag settings.muteQuips true
```

Confirm: "[Name] will stay quiet for now. Run /pokebuddy unmute when you want to hear from them again."

---

## /pokebuddy unmute

Re-enable periodic quips.

```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" set-flag settings.muteQuips false
```

Confirm: "[Name] is back! They'll chime in occasionally as you work."

---

## /pokebuddy off

Hide Pokebuddy for the session.

```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" set-flag enabled false
```

Confirm: "Pokebuddy is resting. Your XP will resume next session. Use /pokebuddy show to wake them up."

---

## /pokebuddy cancel-evolution

Cancel a pending evolution (the "B button" mechanic).

```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" read
```

If `evolutionPending` is false, respond: "There's no pending evolution to cancel right now."

If true:
```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" clear-flag evolutionPending
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" set-flag evolutionCancelledUntil <currentLevel+1>
```

Confirm: "Got it! [Name] stopped evolving. They'll have another chance at level [currentLevel+1]."

---

## /pokebuddy settings

View and adjust settings.

```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" read
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
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" set-flag <key> <value>
```

Confirm the change.

---

## Error handling

If `node dist/state.js read` fails (exits non-zero with "NO_STATE"):
→ Prompt the user to run `/pokebuddy setup` first.

If `pokeget` is not available:
→ Skip sprite rendering, show a text-only fallback with just the Pokémon name.
→ Optionally mention: "Install `pokeget` for sprite rendering: `cargo install pokeget`"
