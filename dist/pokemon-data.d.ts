export interface FirstStagePokemon {
    species: string;
    pokedexId: number;
}
export interface EvolutionEntry {
    evolvesAt: number;
    evolvesInto: string;
}
export interface Nature {
    name: string;
    personalityDescription: string;
    personalityAdjective: string;
    statEffect: string;
}
export interface XpEntry {
    level: number;
    xp: number;
}
export interface BallMilestone {
    ballType: string;
    xpMilestone: number;
    catchRate: number;
}
export declare const FIRST_STAGE_POKEMON: FirstStagePokemon[];
export declare const EVOLUTION_CHAINS: Record<string, EvolutionEntry>;
export declare const NATURES: Nature[];
export declare const XP_TABLE: XpEntry[];
export declare function getLevelForXp(totalXp: number): number;
export declare function getXpForLevel(level: number): number;
export declare function getNextEvolutionLevel(species: string): number | null;
export declare function getEvolvedSpecies(species: string): string | null;
export declare function getRandomNature(): Nature;
export declare function getRandomStarter(): FirstStagePokemon;
export declare function getThreeRandomStarters(): [FirstStagePokemon, FirstStagePokemon, FirstStagePokemon];
export declare const SHINY_CHARM_THRESHOLD = 25;
export declare const BALL_MILESTONES: BallMilestone[];
//# sourceMappingURL=pokemon-data.d.ts.map