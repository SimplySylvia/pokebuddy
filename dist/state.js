import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import { getLevelForXp, getXpForLevel, getEvolvedSpecies, getNextEvolutionLevel, } from "./pokemon-data.js";
// ---------------------------------------------------------------------------
// State file path
// ---------------------------------------------------------------------------
function getStateDir() {
    const pluginData = process.env["CLAUDE_PLUGIN_DATA"];
    if (pluginData)
        return pluginData;
    return path.join(os.homedir(), ".claude", "plugin-data", "pokebuddy");
}
function getStatePath() {
    return path.join(getStateDir(), "pokebuddy-state.json");
}
// ---------------------------------------------------------------------------
// Read / write
// ---------------------------------------------------------------------------
export function readState() {
    const statePath = getStatePath();
    try {
        const raw = fs.readFileSync(statePath, "utf-8");
        return JSON.parse(raw);
    }
    catch {
        return null;
    }
}
export function writeState(state) {
    const stateDir = getStateDir();
    const statePath = getStatePath();
    const tmpPath = statePath + ".tmp";
    if (!fs.existsSync(stateDir)) {
        fs.mkdirSync(stateDir, { recursive: true });
    }
    fs.writeFileSync(tmpPath, JSON.stringify(state, null, 2), "utf-8");
    fs.renameSync(tmpPath, statePath);
}
export function getActivePokemon(state) {
    return state.party[state.activeSlot] ?? null;
}
// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------
export function initState(species, pokedexId, nature, nickname = null) {
    const isEgg = species === "egg";
    const pokemon = {
        species,
        pokedexId,
        nickname,
        nature,
        level: 5,
        xp: 0,
        shiny: false,
        evolutionStage: 1,
        caughtAt: new Date().toISOString(),
        personality: "",
        hatchAt: isEgg ? 25 : null,
    };
    const state = {
        version: 1,
        enabled: true,
        activeSlot: 0,
        totalPrompts: 0,
        totalXP: 0,
        shinyCharm: false,
        evolutionPending: false,
        evolutionCancelledUntil: null,
        quipTriggered: false,
        inventory: { pokeball: 0, greatball: 0, ultraball: 0, masterball: 0 },
        party: [pokemon],
        pokedex: isEgg ? [] : [pokedexId],
        settings: {
            quipFrequency: 0.15,
            muteQuips: false,
            showSpriteOnSession: true,
        },
    };
    writeState(state);
    return state;
}
// ---------------------------------------------------------------------------
// award-xp — the hot path
// ---------------------------------------------------------------------------
export function awardXp(charCount) {
    const state = readState();
    if (!state)
        throw new Error("No state file found. Run /pokebuddy setup first.");
    if (!state.enabled)
        return state;
    const pokemon = state.party[state.activeSlot];
    if (!pokemon)
        return state;
    // Handle egg hatching
    if (pokemon.hatchAt !== null && pokemon.hatchAt > 0) {
        pokemon.hatchAt -= 1;
        state.totalPrompts += 1;
        writeState(state);
        return state;
    }
    const xpEarned = Math.max(1, Math.floor(charCount / 100));
    const prevLevel = pokemon.level;
    pokemon.xp += xpEarned;
    state.totalXP += xpEarned;
    state.totalPrompts += 1;
    const newLevel = getLevelForXp(pokemon.xp);
    pokemon.level = newLevel;
    // Check evolution threshold
    if (newLevel > prevLevel) {
        const evoLevel = getNextEvolutionLevel(pokemon.species);
        const cancelledUntil = state.evolutionCancelledUntil ?? 0;
        if (evoLevel !== null &&
            newLevel >= evoLevel &&
            newLevel > cancelledUntil &&
            !state.evolutionPending) {
            state.evolutionPending = true;
        }
    }
    // Roll quip trigger
    if (!state.settings.muteQuips && Math.random() < state.settings.quipFrequency) {
        state.quipTriggered = true;
    }
    writeState(state);
    return state;
}
// ---------------------------------------------------------------------------
// applyEvolution — called after the evolution sequence plays out
// ---------------------------------------------------------------------------
export function applyEvolution() {
    const state = readState();
    if (!state)
        throw new Error("No state file found.");
    const pokemon = state.party[state.activeSlot];
    if (!pokemon)
        return state;
    const evolved = getEvolvedSpecies(pokemon.species);
    if (evolved) {
        pokemon.species = evolved;
        pokemon.evolutionStage += 1;
        // Reset evolutionCancelledUntil after successful evolution
        state.evolutionCancelledUntil = null;
    }
    state.evolutionPending = false;
    writeState(state);
    return state;
}
// ---------------------------------------------------------------------------
// Helpers for shell hooks (simple flag mutations)
// ---------------------------------------------------------------------------
export function setFlag(flag, value) {
    const state = readState();
    if (!state)
        throw new Error("No state file found.");
    const parts = flag.split(".");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let obj = state;
    for (let i = 0; i < parts.length - 1; i++) {
        obj = obj[parts[i]];
    }
    const lastKey = parts[parts.length - 1];
    if (value === "true")
        obj[lastKey] = true;
    else if (value === "false")
        obj[lastKey] = false;
    else if (!isNaN(Number(value)))
        obj[lastKey] = Number(value);
    else
        obj[lastKey] = value;
    writeState(state);
    return state;
}
export function clearFlag(flag) {
    const state = readState();
    if (!state)
        throw new Error("No state file found.");
    const parts = flag.split(".");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let obj = state;
    for (let i = 0; i < parts.length - 1; i++) {
        obj = obj[parts[i]];
    }
    const lastKey = parts[parts.length - 1];
    obj[lastKey] = false;
    writeState(state);
    return state;
}
export function setPersonality(description) {
    const state = readState();
    if (!state)
        throw new Error("No state file found.");
    const pokemon = state.party[state.activeSlot];
    if (pokemon)
        pokemon.personality = description;
    writeState(state);
    return state;
}
export function getXpProgress(pokemon) {
    const currentLevelXp = getXpForLevel(pokemon.level);
    const nextLevelXp = getXpForLevel(pokemon.level + 1);
    const xpIntoLevel = pokemon.xp - currentLevelXp;
    const xpNeeded = nextLevelXp - currentLevelXp;
    const progressPercent = xpNeeded > 0 ? Math.round((xpIntoLevel / xpNeeded) * 100) : 100;
    return {
        level: pokemon.level,
        xp: pokemon.xp,
        xpForCurrentLevel: currentLevelXp,
        xpForNextLevel: nextLevelXp,
        progressPercent,
        nextEvolutionLevel: getNextEvolutionLevel(pokemon.species),
        evolvedSpecies: getEvolvedSpecies(pokemon.species),
    };
}
// ---------------------------------------------------------------------------
// CLI interface — called from shell hooks
// ---------------------------------------------------------------------------
const [, , command, ...args] = process.argv;
if (command) {
    try {
        switch (command) {
            case "read": {
                const state = readState();
                if (!state) {
                    process.stderr.write("NO_STATE\n");
                    process.exit(1);
                }
                process.stdout.write(JSON.stringify(state, null, 2) + "\n");
                break;
            }
            case "init": {
                const [species, pokedexIdStr, nature, nickname] = args;
                if (!species || !pokedexIdStr || !nature) {
                    process.stderr.write("Usage: state.js init <species> <pokedexId> <nature> [nickname]\n");
                    process.exit(1);
                }
                const newState = initState(species, parseInt(pokedexIdStr, 10), nature, nickname ?? null);
                process.stdout.write(JSON.stringify(newState, null, 2) + "\n");
                break;
            }
            case "award-xp": {
                const [charCountStr] = args;
                if (!charCountStr) {
                    process.stderr.write("Usage: state.js award-xp <charCount>\n");
                    process.exit(1);
                }
                const updatedState = awardXp(parseInt(charCountStr, 10));
                process.stdout.write(JSON.stringify(updatedState, null, 2) + "\n");
                break;
            }
            case "set-flag": {
                const [flag, value] = args;
                if (!flag || value === undefined) {
                    process.stderr.write("Usage: state.js set-flag <flag> <value>\n");
                    process.exit(1);
                }
                setFlag(flag, value);
                break;
            }
            case "clear-flag": {
                const [flag] = args;
                if (!flag) {
                    process.stderr.write("Usage: state.js clear-flag <flag>\n");
                    process.exit(1);
                }
                clearFlag(flag);
                break;
            }
            case "update-evolution": {
                const updatedState = applyEvolution();
                process.stdout.write(JSON.stringify(updatedState, null, 2) + "\n");
                break;
            }
            case "set-personality": {
                const description = args.join(" ");
                if (!description) {
                    process.stderr.write("Usage: state.js set-personality <text>\n");
                    process.exit(1);
                }
                setPersonality(description);
                break;
            }
            default:
                process.stderr.write(`Unknown command: ${command}\n`);
                process.exit(1);
        }
    }
    catch (err) {
        process.stderr.write(String(err) + "\n");
        process.exit(1);
    }
}
//# sourceMappingURL=state.js.map