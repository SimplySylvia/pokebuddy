export interface Inventory {
    pokeball: number;
    greatball: number;
    ultraball: number;
    masterball: number;
}
export interface PokemonState {
    species: string;
    pokedexId: number;
    nickname: string | null;
    nature: string;
    level: number;
    xp: number;
    shiny: boolean;
    evolutionStage: number;
    caughtAt: string;
    personality: string;
    hatchAt: number | null;
}
export interface Settings {
    quipFrequency: number;
    muteQuips: boolean;
    showSpriteOnSession: boolean;
}
export interface PokebuddyState {
    version: number;
    enabled: boolean;
    activeSlot: number;
    totalPrompts: number;
    totalXP: number;
    shinyCharm: boolean;
    evolutionPending: boolean;
    evolutionCancelledUntil: number | null;
    quipTriggered: boolean;
    inventory: Inventory;
    party: PokemonState[];
    pokedex: number[];
    settings: Settings;
}
export declare function readState(): PokebuddyState | null;
export declare function writeState(state: PokebuddyState): void;
export declare function getActivePokemon(state: PokebuddyState): PokemonState | null;
export declare function initState(species: string, pokedexId: number, nature: string, nickname?: string | null): PokebuddyState;
export declare function awardXp(charCount: number): PokebuddyState;
export declare function applyEvolution(): PokebuddyState;
export declare function setFlag(flag: string, value: string): PokebuddyState;
export declare function clearFlag(flag: string): PokebuddyState;
export declare function setPersonality(description: string): PokebuddyState;
export interface XpProgress {
    level: number;
    xp: number;
    xpForCurrentLevel: number;
    xpForNextLevel: number;
    progressPercent: number;
    nextEvolutionLevel: number | null;
    evolvedSpecies: string | null;
}
export declare function getXpProgress(pokemon: PokemonState): XpProgress;
//# sourceMappingURL=state.d.ts.map