# Starter Selection Display: Name, Shiny, and Nature

**Date:** 2026-04-08

## Summary

When the setup flow presents 3 starter options in Step 3a, each option should show its name, nature, and whether it is shiny — all pre-rolled at display time so the user can make an informed choice.

## Scope

Changes are limited to `skills/companion/SKILL.md`. No TypeScript changes or recompilation required.

## Design

### Step 3a — Data gathering

Replace the existing `getThreeRandomStarters` call with an inline node call that also pre-rolls a nature and a 1/20 shiny chance for each option:

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

### Step 3a — Display labels

Labels change from:
```
── Option 1: Charmander (#4) ──
```
to:
```
── Option 1: Charmander (#4) | Jolly nature ──
── Option 1: ✨ Charmander (#4) | Jolly nature  [SHINY] ──
```

- Nature name always shown
- `✨` prefix and `[SHINY]` suffix only appended when `shiny=true`
- Sprite calls receive `--shiny` flag when `shiny=true`

### Step 5 — Nature threading

Remove the `getRandomNature()` call in Step 5. Instead, use `options[chosen-1].nature` from the pre-rolled data — the chosen starter's nature is already determined.

### Step 6 — Shiny flag

After `state.js init`, add a conditional: if the chosen option had `shiny=true`, run:
```bash
node "${CLAUDE_PLUGIN_ROOT}/dist/state.js" set-flag party.0.shiny true
```

## Trade-offs

- Pre-rolling nature and shiny at display time makes selection more interesting (you can choose based on nature/shiny)
- 1/20 shiny rate is intentionally elevated from the standard 1/4096 to make the mechanic fun and visible during setup
- No new functions or compiled code needed; fits the existing inline `node -e` pattern in the skill
