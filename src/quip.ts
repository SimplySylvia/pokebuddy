import { NATURES } from "./pokemon-data.js";
import type { PokemonState } from "./state.js";

export function buildQuipPrompt(pokemon: PokemonState, recentContext: string): string {
  const nature = NATURES.find((n) => n.name === pokemon.nature);
  const name = pokemon.nickname ?? pokemon.species;
  const personalityDesc = nature?.personalityDescription ?? "enthusiastic about coding";
  const personalityAdj = nature?.personalityAdjective ?? "enthusiastic";

  return `You are ${name}, a ${pokemon.nature} ${pokemon.species} at level ${pokemon.level}.
Your personality: ${personalityDesc}.
The developer just worked on: ${recentContext}.
Generate a short, in-character comment (1-2 sentences). Stay in character. Be ${personalityAdj}.
Do not use the developer's name. Do not mention Claude or AI. Keep it light and fun.
Respond with ONLY the quip — no prefixes, no explanations.`;
}

// ---------------------------------------------------------------------------
// CLI interface — called from stop-hook.sh:
//   node dist/quip.js <stateJsonBase64> <contextText>
// ---------------------------------------------------------------------------

const [,, stateB64, ...contextParts] = process.argv;

if (stateB64) {
  try {
    const stateJson = Buffer.from(stateB64, "base64").toString("utf-8");
    const state = JSON.parse(stateJson) as { party: PokemonState[]; activeSlot: number };
    const pokemon = state.party[state.activeSlot];
    if (!pokemon) {
      process.stderr.write("No active pokemon in state\n");
      process.exit(1);
    }

    const context = contextParts.join(" ").trim() || "their code";
    // Truncate context to ~20 words
    const words = context.split(/\s+/).slice(0, 20).join(" ");

    const prompt = buildQuipPrompt(pokemon, words);
    process.stdout.write(prompt + "\n");
  } catch (err) {
    process.stderr.write(String(err) + "\n");
    process.exit(1);
  }
}
