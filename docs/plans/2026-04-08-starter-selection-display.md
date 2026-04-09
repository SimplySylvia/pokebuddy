# Starter Selection Display Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Pre-roll a nature and 1/20 shiny chance per starter option in the setup flow, and display them alongside the sprite so the user can make an informed choice.

**Architecture:** All changes are in `skills/companion/SKILL.md` — no TypeScript or compilation needed. The existing `node -e` data-gathering call is extended to output natures and shiny flags; the display labels and sprite calls are updated to reflect them; nature threading to Step 5 and shiny flag to Step 6 complete the wiring.

**Tech Stack:** SKILL.md instruction text, inline `node -e` calls, `pokemon-data.js` (already compiled)

---

### Task 1: Extend the data-gathering call in Step 3a

**Files:**
- Modify: `skills/companion/SKILL.md:52-58`

**Step 1: Replace the node -e data-gathering block**

Current block (lines 52-58):
```bash
node -e "
const { getThreeRandomStarters } = await import('${CLAUDE_PLUGIN_ROOT}/dist/pokemon-data.js');
const [a, b, c] = getThreeRandomStarters();
console.log(JSON.stringify([a, b, c]));
"
```

Replace with:
```bash
node -e "
const { getThreeRandomStarters, getRandomNature } = await import('${CLAUDE_PLUGIN_ROOT}/dist/pokemon-data.js');
const options = getThreeRandomStarters().map(p => ({
  ...p,
  nature: getRandomNature(),
  shiny: Math.random() < 1/20
}));
console.log(JSON.stringify(options));
"
```

The output is now an array of `{species, pokedexId, nature, shiny}` objects. Refer to them as `options[0]`, `options[1]`, `options[2]` (or `a`, `b`, `c` — your choice) in subsequent steps.

**Step 2: Commit**
```bash
git add skills/companion/SKILL.md
git commit -m "feat: pre-roll nature and shiny for each starter option"
```

---

### Task 2: Update the display labels and sprite calls in Step 3a

**Files:**
- Modify: `skills/companion/SKILL.md:62-64`

**Step 1: Replace the single-bash display block**

Current block (line 62-64):
```bash
printf "── Option 1: [a.name] (#[a.id]) ──\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" [a.id] --hide-name && printf "\n── Option 2: [b.name] (#[b.id]) ──\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" [b.id] --hide-name && printf "\n── Option 3: [c.name] (#[c.id]) ──\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" [c.id] --hide-name
```

Replace with (label format and `--shiny` flag are the key changes):
```bash
printf "── Option 1: [✨ if a.shiny][a.name] (#[a.id]) | [a.nature.name] nature ──\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" [a.id] --hide-name [--shiny if a.shiny] && printf "\n── Option 2: [✨ if b.shiny][b.name] (#[b.id]) | [b.nature.name] nature ──\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" [b.id] --hide-name [--shiny if b.shiny] && printf "\n── Option 3: [✨ if c.shiny][c.name] (#[c.id]) | [c.nature.name] nature ──\n" && node "${CLAUDE_PLUGIN_ROOT}/dist/sprites.js" [c.id] --hide-name [--shiny if c.shiny]
```

Label rules to document in SKILL.md:
- Always include `| [nature.name] nature` after the Pokédex ID
- If `shiny=true`: prefix name with `✨ ` and append `--shiny` to the sprite call
- If `shiny=false`: no prefix, no `--shiny` flag

**Step 2: Commit**
```bash
git add skills/companion/SKILL.md
git commit -m "feat: show nature and shiny indicator in starter option labels"
```

---

### Task 3: Thread the pre-rolled nature through to Step 5

**Files:**
- Modify: `skills/companion/SKILL.md:73-80`

**Step 1: Replace the Step 5 nature block**

Current Step 5 opens with:
> "Pick a random nature:" followed by a `node -e` call to `getRandomNature()`.

Replace the instruction and the entire node -e block with:
> "Use the nature that was pre-rolled for the chosen option (e.g. `options[0].nature` for Option 1). No additional roll is needed."

The `nature` variable for the rest of Step 5 and Step 6 is now `options[chosen-1].nature` (the full `Nature` object, with `.name`, `.personalityDescription`, etc.).

**Step 2: Commit**
```bash
git add skills/companion/SKILL.md
git commit -m "feat: use pre-rolled nature from chosen starter option"
```

---

### Task 4: Apply shiny flag after state init in Step 6

**Files:**
- Modify: `skills/companion/SKILL.md:88-91`

**Step 1: Add conditional shiny flag after the init call**

After the existing init line:
```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" init <species> <pokedexId> <nature> "<nickname or empty>"
```

Add the instruction:
> "If the chosen option had `shiny=true`, also run:"
```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" set-flag party.0.shiny true
```

**Step 2: Commit**
```bash
git add skills/companion/SKILL.md
git commit -m "feat: persist shiny flag when chosen starter was shiny"
```

---

### Task 5: Manual verification

**Step 1:** Run `/pokebuddy setup` and choose mode "Choose a starter"

**Step 2:** Confirm the output shows all three options with:
- Nature name in the label (e.g. `| Jolly nature`)
- `✨` prefix and shiny sprite for any shiny option (run a few times — at 1/20 odds you should see one within ~5 attempts)
- Non-shiny options render normally with no prefix

**Step 3:** Pick a shiny option (if one appeared) and confirm:
- `state.js read` shows `"shiny": true` on `party[0]`
- `/pokebuddy show` renders the shiny sprite and shows the `✨` prefix

**Step 4:** Confirm the nature shown at selection matches the nature recorded in state (`party[0].nature`)
