# Pokebuddy — Product Requirements Document

**Version:** 1.0
**Date:** April 8, 2026
**Status:** Draft

---

## Overview

Pokebuddy is a Claude Code plugin that brings a progression-driven Pokémon companion system to the developer's terminal. Unlike Claude Code's built-in `/buddy` feature — a Tamagotchi-style companion with no progression mechanics — Pokebuddy layers in XP, leveling, evolution, catching, and emergent personality to create a long-term engagement loop tied directly to a developer's real coding activity.

The plugin operates as a fully separate system under the `/pokebuddy` namespace, coexisting peacefully alongside `/buddy`. It leverages Claude Code's hook architecture, the Skills system for slash commands, and the `pokeget-rs` CLI for fast, beautiful ANSI terminal sprites drawn from Gen 1-8 (~898 Pokémon).

---

## Goals

The primary goal of v1 is to deliver a functional, delightful core loop: a developer starts using Claude Code, picks a starter Pokémon, earns XP through real prompts, watches their Pokémon level up and evolve over days of use, and receives short personality-driven quips that make the experience feel alive. The Pokéball catching system and full rarity tiers follow in v2.

**What Pokebuddy must do:**
- Greet new users with a starter selection experience using rendered terminal sprites
- Track XP earned per prompt and display level progression tied to canonical Pokémon evolution thresholds
- Trigger brief, in-character quips periodically (not on every prompt) using nature-driven personality
- Persist all state across sessions and Claude Code updates without data loss
- Detect whether `pokeget` is installed and guide the user through setup if not

**What Pokebuddy must not do:**
- Break or conflict with the built-in `/buddy` system
- Fire a quip on every single prompt (quip fatigue is a real risk)
- Block Claude's main response loop with synchronous operations
- Support Gen 9+ Pokémon where no terminal sprites exist

---

## User Stories

**As a developer using Claude Code daily,** I want a Pokémon companion that grows alongside my actual work, so that I have a reason to keep using the tool and feel rewarded for extended sessions.

**As a first-time user,** I want to pick a starter Pokémon from a visual sprite-based selection screen, so that I immediately feel ownership and emotional investment in my companion.

**As a long-term user,** I want my Pokémon to evolve after enough prompts, so that progression feels meaningful and milestones feel earned.

**As someone who finds constant interruptions annoying,** I want quips to appear infrequently and feel contextual — not random noise — so that my companion adds delight without becoming friction.

**As a collector,** I want to encounter and catch new Pokémon by spending Pokéballs earned through activity, so that there's always something new to find.

---

## Architecture

### Plugin Structure

Pokebuddy is packaged as a standard Claude Code plugin with the following directory layout:

```
pokebuddy/
├── .claude-plugin/
│   └── plugin.json          # Manifest: name, version, description, permissions
├── skills/
│   └── pokebuddy/
│       └── SKILL.md         # Primary /pokebuddy slash command and all subcommands
├── hooks/
│   ├── session-start.sh     # Initialize state, check pokeget binary
│   ├── prompt-submit.sh     # Award XP, roll for quip trigger
│   └── stop-hook.sh         # Generate personality quip via LLM if triggered
└── lib/
    ├── state.ts             # Read/write pokebuddy-state.json
    ├── sprites.ts           # pokeget-rs wrapper
    ├── pokemon-data.ts      # Species, evolutions, natures lookup tables
    └── quip.ts              # Prompt template construction for quip generation
```

### Persistence

All state lives at `${CLAUDE_PLUGIN_DATA}/pokebuddy-state.json`. This path is managed by Claude Code, survives plugin updates, and is distinct from the built-in `/buddy`'s `~/.claude.json` storage. The `SessionStart` hook is responsible for bootstrapping the file if it doesn't exist and migrating schema versions when needed.

### Hook Integration Points

| Hook Event | Handler | Purpose |
|---|---|---|
| `SessionStart` | `session-start.sh` | Load state, check `pokeget` binary, display active Pokémon sprite |
| `UserPromptSubmit` | `prompt-submit.sh` | Award XP, check evolution threshold, set quip trigger flag in state |
| `Stop` | `stop-hook.sh` | If quip flag set: generate personality quip via LLM prompt, clear flag |
| `PreCompact` | inline | Write current state to disk before context compaction |
| `PostCompact` | inline | Reload state context summary after compaction |

All hook handlers should be `async: true` to avoid blocking Claude's main response. The `Stop` hook can return a `block` decision to inject a quip after Claude's response without interrupting it mid-generation.

### Sprite Rendering via pokeget-rs

Pokémon sprites are rendered via the `pokeget` CLI, a Rust binary that embeds PokéSprite assets directly and outputs ANSI-colored Unicode half-block art in ~6ms with no network requests. Integration is via `child_process.execFile` in TypeScript:

```typescript
import { execFile } from 'child_process';
import { promisify } from 'util';
const execFileAsync = promisify(execFile);

async function getPokeSprite(
  pokemon: string | number,
  options?: { shiny?: boolean; hideName?: boolean }
): Promise<string> {
  const args: string[] = [String(pokemon)];
  if (options?.shiny) args.push('--shiny');
  if (options?.hideName) args.push('--hide-name');
  const { stdout } = await execFileAsync('pokeget', args);
  return stdout;
}
```

The plugin checks for `pokeget` availability at `SessionStart` via `which pokeget`. If absent, it displays installation instructions (`cargo install pokeget`) and falls back to a text-only mode with simple ASCII representations.

**Terminal width constraint:** Sprites are approximately 68 columns wide. For multi-sprite displays (e.g., starter selection), sprites must be stacked vertically rather than side-by-side, as three sprites horizontally would require 200+ columns. Terminal width is detected via `process.stdout.columns` and layout adapts accordingly.

---

## State Schema

```json
{
  "version": 1,
  "enabled": true,
  "activeSlot": 0,
  "totalPrompts": 0,
  "totalXP": 0,
  "shinyCharm": false,
  "inventory": {
    "pokeball": 0,
    "greatball": 0,
    "ultraball": 0,
    "masterball": 0
  },
  "party": [
    {
      "species": "charmander",
      "pokedexId": 4,
      "nickname": null,
      "nature": "Jolly",
      "level": 5,
      "xp": 0,
      "shiny": false,
      "evolutionStage": 1,
      "caughtAt": "2026-04-08T00:00:00Z",
      "personality": "A cheerful fire lizard who celebrates every successful build"
    }
  ],
  "pokedex": [4],
  "quipTriggered": false,
  "settings": {
    "quipFrequency": 0.15,
    "muteQuips": false,
    "showSpriteOnSession": true
  }
}
```

The `quipTriggered` flag acts as a signal between the `UserPromptSubmit` hook (which rolls for quip probability) and the `Stop` hook (which generates and displays the quip). This decouples the trigger decision from the generation step.

---

## Feature Specifications

### First-Time Setup (`/pokebuddy setup`)

On first run (when no state file exists), the plugin launches a starter selection flow:

1. Display a welcome message introducing Pokebuddy and the concept of earning XP through prompts.
2. Randomly select 3 Pokémon from the starter pool (canonical game starters or any first-stage Gen 1-8 species).
3. Render each Pokémon sprite vertically using `pokeget --hide-name` followed by custom name labels, adapting to terminal width.
4. Prompt the user to pick 1, 2, or 3.
5. Assign a random nature to the chosen Pokémon from the full 25-nature pool.
6. Fire a one-time LLM call to generate a short personality description (1-2 sentences) influenced by the species and nature. Store this in the `personality` field.
7. Write initial state to `${CLAUDE_PLUGIN_DATA}/pokebuddy-state.json`.
8. Confirm the starter and display its personality in the terminal.

An alternative "egg hatching" flow can be offered as an opt-in variant: the user receives a mystery egg that renders as an egg sprite and hatches into a random Pokémon after 25 prompts. This adds mystery and delayed gratification but delays emotional connection. Both modes should be supported at launch.

### XP and Leveling System

XP is awarded on every `UserPromptSubmit` event. The base formula is:

- **XP per prompt:** `max(1, floor(characterCount / 100))`
- A 50-character prompt earns 1 XP; a 500-character prompt earns 5 XP.

Level thresholds follow a quadratic curve inspired by Pokémon's "Medium Slow" experience group. Suggested breakpoints:

| Level | Cumulative XP Required |
|---|---|
| 5 (starter) | 0 |
| 10 | 100 |
| 16 (first evo) | 250 |
| 20 | 400 |
| 32 (second evo) | 900 |
| 36 | 1,100 |
| 50 | 2,500 |
| 100 | 10,000 |

These thresholds are designed so a developer submitting ~15-20 prompts per day would reach first evolution in roughly 1-2 weeks, and second evolution in 1-2 months — pacing that mirrors the original games' intended engagement arc.

When a level-up event crosses a canonical evolution threshold, the evolution sequence triggers automatically (see Evolution below). The `UserPromptSubmit` hook writes updated XP and level to state; if an evolution threshold was crossed, it sets an `evolutionPending` flag that the `Stop` hook renders after Claude's next response.

### Evolution System

Canonical evolution thresholds from the games are stored in `pokemon-data.ts` for all supported Gen 1-8 species. Common reference points:

- **Level 7:** Caterpie → Metapod
- **Level 16:** Most first-stage starter evolutions (Bulbasaur, Charmander, Squirtle lines)
- **Level 32-36:** Most second-stage evolutions
- **Level 64:** Zweilous → Hydreigon (latest standard threshold)

When `evolutionPending` is detected by the `Stop` hook, the plugin renders the following sequence to stdout:

1. Display current form sprite (`pokeget {species}`)
2. Print: `What? {Name} is evolving!`
3. Brief pause (simulated via sequential output lines)
4. Print: `{Name} evolved into {evolvedSpecies}!`
5. Display evolved form sprite (`pokeget {evolvedSpecies}`)
6. Update state: new species, increment evolutionStage, clear flag

The user should have the ability to cancel evolution by running `/pokebuddy cancel-evolution` before the next prompt — a faithful recreation of the "B button" mechanic from the games. If cancelled, the evolution threshold resets to the next level above the current one (+1 level grace period).

### Nature and Personality-Driven Quips

Each Pokémon is assigned one of 25 natures at acquisition time. The nature determines the "voice" used for all LLM-generated quips. A quip fires when:

1. The `UserPromptSubmit` hook rolls a random float against `settings.quipFrequency` (default: 0.15 — a 15% chance per prompt).
2. If triggered, `quipTriggered` is set to `true` in state.
3. The `Stop` hook reads this flag and, if set, constructs a quip prompt and sends it to Claude.

The quip prompt template:

```
You are {nickname or species}, a {nature} {species} at level {level}.
Your personality: {naturePersonalityDescription}.
The user just worked on: {briefContextSummary}.
Generate a short, in-character comment (1-2 sentences). Stay in character. Be {personalityAdjective}.
Do not use the user's name. Do not mention Claude. Keep it light.
```

The `briefContextSummary` is a short (≤20 word) summary of the user's most recent prompt topic, extracted by the quip hook before generating. Quip output is printed below Claude's response, prefixed with the Pokémon's name and a small emoji indicator.

**Nature-to-Personality Reference:**

| Nature | Stat Effect | Personality Voice | Example Quip |
|---|---|---|---|
| Adamant | +Atk / −SpAtk | Determined, headstrong | "Just push through it. Brute force works." |
| Bashful | Neutral | Shy, self-conscious | "Oh, um... that code looks... nice, I think?" |
| Bold | +Def / −Atk | Confident, resilient | "Stand your ground. This test suite WILL pass." |
| Brave | +Atk / −Spd | Fearless, charges in | "Ship it! We'll fix bugs in production!" |
| Calm | +SpDef / −Atk | Peaceful, patient | "Take a breath. The solution will come." |
| Careful | +SpDef / −SpAtk | Cautious, methodical | "Did you check edge cases? Double-check." |
| Docile | Neutral | Gentle, agreeable | "Whatever you think is best! I trust you." |
| Gentle | +SpDef / −Def | Kind, nurturing | "You're doing great. Don't forget to rest." |
| Hardy | Neutral | Tough, no-nonsense | "Keep going. Code doesn't write itself." |
| Hasty | +Spd / −Def | Impatient, restless | "Come ON, let's move to the next feature!" |
| Impish | +Def / −SpAtk | Playful, prankster | "Oops, did you mean to delete that file? 😈" |
| Jolly | +Spd / −SpAtk | Cheerful, optimistic | "That refactor was BEAUTIFUL! High five!" |
| Lax | +Def / −SpDef | Laid-back, carefree | "Eh, it compiles. Ship it." |
| Lonely | +Atk / −Def | Solitary, introverted | "...I noticed you fixed that memory leak. Nice." |
| Mild | +SpAtk / −Def | Soft-spoken, gentle | "Perhaps consider a more elegant approach?" |
| Modest | +SpAtk / −Atk | Humble, intellectual | "The algorithmic complexity here is fascinating." |
| Naive | +Spd / −SpDef | Innocent, trusting | "Wow, you know SO much about TypeScript!" |
| Naughty | +Atk / −SpDef | Rebellious, feisty | "Linting rules? More like linting suggestions." |
| Quiet | +SpAtk / −Spd | Contemplative, deep | "...interesting architectural choice. *stares*" |
| Quirky | Neutral | Eccentric, unpredictable | "What if we rewrote everything in Haskell?" |
| Rash | +SpAtk / −SpDef | Impetuous, hot-headed | "JUST DEPLOY IT ALREADY!" |
| Relaxed | +Def / −Spd | Chill, unhurried | "No rush. Good code takes time. *yawns*" |
| Sassy | +SpDef / −Spd | Snarky, witty | "Oh, ANOTHER todo comment. Classic." |
| Serious | Neutral | Focused, stoic | "Proceed. We have work to do." |
| Timid | +Spd / −Atk | Shy, cautious | "M-maybe add some error handling first...?" |

### Pokéball Earning and Catching System (v2)

Pokéballs are awarded at XP milestones and spent via `/pokebuddy catch`. This feature is scoped to v2 but the state schema supports it from day one.

**Ball award thresholds:**

| Ball Type | XP Milestone | Catch Rate |
|---|---|---|
| Poké Ball | Every 500 XP | 40% |
| Great Ball | Every 2,000 XP | 60% |
| Ultra Ball | Every 5,000 XP | 80% |
| Master Ball | 50,000 XP (once only) | 100% |

**Catch flow (triggered by `/pokebuddy catch`):**

1. Check inventory for available balls. If empty, display a message about how many XP are needed for the next ball.
2. Prompt the user to select a ball type if multiple are available.
3. Deduct the ball from inventory.
4. Generate a random wild Pokémon, weighted by rarity tier: Common 60%, Uncommon 25%, Rare 10%, Epic 4%, Legendary 1%.
5. Render the wild Pokémon sprite via `pokeget`.
6. Roll catch probability based on ball type and rarity modifier (Legendary Pokémon have reduced catch rates regardless of ball).
7. Display 1-3 "shake" lines to build tension, then reveal success or failure.
8. On success: assign a random nature, generate a personality description, add to party (max 6), and record in `pokedex`.
9. On failure: display an escape message. The ball is spent regardless.

### Shiny Variants

Every Pokémon encounter rolls for shiny status independently of catch success. Base rate: **1/4,096**. With the Shiny Charm unlock (earned after registering 25+ unique species in the Pokédex), the rate improves to **1/512**.

Shiny Pokémon are displayed via `pokeget --shiny` and marked with a ✨ in all UI surfaces (stat cards, party view, Pokédex). A shiny encounter triggers a special message and a distinct visual treatment (e.g., an ASCII sparkle border around the sprite).

### Slash Commands

All commands are available under the `/pokebuddy` namespace (or `pokebuddy:command` in plugin-namespaced contexts).

| Command | Description |
|---|---|
| `/pokebuddy setup` | First-time setup flow: starter selection or egg mode |
| `/pokebuddy show` | Display active Pokémon sprite and basic stats |
| `/pokebuddy stats` | Full stat card: level, XP, nature, personality, evolution progress |
| `/pokebuddy party` | View all Pokémon in the party (up to 6) |
| `/pokebuddy switch <slot>` | Change the active Pokémon (1-6) |
| `/pokebuddy catch` | Spend a Pokéball to encounter a wild Pokémon (v2) |
| `/pokebuddy pokedex` | View caught species registry and completion percentage |
| `/pokebuddy mute` | Silence periodic quips |
| `/pokebuddy unmute` | Re-enable periodic quips |
| `/pokebuddy off` | Hide Pokebuddy entirely for the session |
| `/pokebuddy cancel-evolution` | Cancel a pending evolution (before next prompt) |
| `/pokebuddy settings` | Adjust quip frequency and display preferences |

---

## Coexistence with `/buddy`

The built-in `/buddy` system is a first-party Anthropic feature using a `Bones + Soul` architecture that deterministically generates a virtual pet from a user hash and stores its personality in `~/.claude.json`. Pokebuddy must not interfere with this system.

Key separation requirements:
- All Pokebuddy commands use the `/pokebuddy` prefix exclusively.
- Pokebuddy state is stored in `${CLAUDE_PLUGIN_DATA}`, never touching `~/.claude.json`.
- Both systems can run simultaneously. Users who enjoy `/buddy` need not disable it to use Pokebuddy.
- Pokebuddy hooks must not intercept or modify `/buddy` lifecycle events.

The two systems serve different motivations: `/buddy` is a casual ambient companion; Pokebuddy is a progression-and-collection experience for users who want long-term engagement hooks.

---

## Technical Risks and Mitigations

**`pokeget` binary dependency.** Pokebuddy requires `cargo install pokeget` or a platform package (AUR, Nix, Conda). Users without a Rust toolchain may find installation friction. Mitigation: the `SessionStart` hook detects `pokeget` absence via `which pokeget` and displays clear installation instructions. A text-only fallback mode (ASCII name display, no sprite rendering) keeps the plugin functional for users who cannot install the binary.

**Gen 9+ sprite coverage gap.** `pokeget-rs` embeds Gen 1-8 sprites only (~898 Pokémon). The PokéSprite project has ceased updates as Pokémon has moved away from pixel sprites. Gen 9 and Gen 10 Pokémon are not available. Mitigation: the plugin's encounter and starter pools are explicitly capped at Gen 1-8. This is documented as a known limitation in the plugin README. A future version could investigate supplementary sprite sources for newer Pokémon.

**Quip generation token cost.** Each personality quip requires a small LLM call from the `Stop` hook. While architecturally supported, accumulated over many sessions this could represent meaningful token usage. Mitigation: quip prompts are kept under 200 input tokens. A per-session quip cap (e.g., maximum 5 quips per session) prevents excessive calls. Response caching by context category could further reduce calls in future versions.

**Hook execution timing.** The `Stop` hook fires after Claude finishes responding. If quip generation takes >1-2 seconds, it creates perceptible lag at the end of every triggered prompt. Mitigation: quip prompts must be minimal. If the `Stop` hook supports `async: true`, quip generation should not block the session from returning to the input prompt.

**Evolution animation sequencing.** Rendering a before/after sprite sequence with a pause requires timed output in a hook context. Mitigation: the evolution handler outputs the full sequence synchronously with brief `sleep` calls between stages, leveraging the shell hook context. A simple, reliable implementation is preferred over a polished animation in v1.

**Terminal width for multi-sprite layouts.** Sprites are ~68 columns; three side-by-side would require 200+ columns, breaking most terminals. Mitigation: multi-sprite displays (starter selection, party view) always stack vertically. Terminal width is read via `process.stdout.columns` and used to determine how many sprites (if any) can be shown horizontally.

---

## V1 Scope vs. V2 Scope

### V1 (Launch)

- First-time setup with starter selection (sprite-based, vertical layout) and egg hatching variant
- XP system tied to prompt character count, awarded via `UserPromptSubmit` hook
- Leveling with canonical Gen 1-8 evolution thresholds
- Evolution sequence with cancel support
- Nature-driven LLM personality quips at 15% per-prompt frequency
- Session start sprite display for active Pokémon
- `pokeget` binary detection with graceful fallback
- Full slash command set (show, stats, party, switch, mute, off, settings)
- State persistence via `${CLAUDE_PLUGIN_DATA}/pokebuddy-state.json`
- Shiny variant support in state schema and display (even if encounters aren't yet live)

### V2

- Pokéball earning system (XP milestones)
- Wild encounter and catching flow with shake animation
- Rarity-tiered encounter pool (Common through Legendary)
- Shiny encounter rolls and Shiny Charm unlock
- Pokédex completion tracking and percentage display
- Per-session quip cap and caching
- Nickname support for party Pokémon
- Gen 9+ sprite supplementary source (if viable)

---

## Success Metrics

Pokebuddy's success is measured by whether it creates a habit loop — developers who install it continue using it over weeks, not just the first day.

**Engagement:** Median active Pokebuddy users should reach their first evolution (level 16, ~250 XP) within 2 weeks of install, indicating sustained daily use. This is the first major milestone and a natural word-of-mouth moment.

**Retention:** 30-day retention among users who complete starter selection should exceed 40%. The presence of a named, leveled companion creates sunk-cost investment that encourages continued use.

**Quip quality:** Quip frequency should feel ambient, not intrusive. If more than 15% of users mute quips within the first week, the default frequency (currently 15%) should be reduced.

**Adoption funnel:** The ratio of users who complete starter selection vs. users who install the plugin should exceed 70%. A low completion rate indicates the onboarding flow has friction that needs resolution.

---

## Open Questions

1. Should nickname support be part of v1 (adds emotional investment) or v2 (adds scope)? The state schema supports it; it's a question of whether the setup flow prompts for it.

2. Can the `Stop` hook's quip calls be made exempt from usage limits, as the built-in `/buddy` reactions reportedly are? This would significantly change the economics of quip generation.

3. Should the starter pool be limited to the 10 canonical trios from the games, or open to any first-stage Gen 1-8 Pokémon? Canonical starters are more recognizable; a broader pool increases novelty.

4. What is the right party cap? The games use 6; Pokebuddy should likely match this, but a lower cap (e.g., 3) for v1 simplifies the party UI.

5. Is a companion web dashboard (Pokédex view, stat charts) worth exploring for a future version, or should Pokebuddy remain terminal-only to stay aligned with the Claude Code use case?
