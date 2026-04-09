import { execFile } from "child_process";
import { promisify } from "util";
const execFileAsync = promisify(execFile);
// Static ASCII egg art fallback (used when pokeget doesn't know "egg")
const EGG_ART = `   ,-.
  / \\  \\
 |     |
  \\   /
   \`-'
  [Egg]`;
export async function getPokeSprite(pokemon, options) {
    const args = [String(pokemon)];
    if (options?.shiny)
        args.push("--shiny");
    if (options?.hideName)
        args.push("--hide-name");
    try {
        const { stdout } = await execFileAsync("pokeget", args);
        return stdout;
    }
    catch (err) {
        // If the species is "egg" and pokeget doesn't support it, use fallback
        if (String(pokemon).toLowerCase() === "egg") {
            return EGG_ART;
        }
        throw err;
    }
}
export async function checkPokegetInstalled() {
    try {
        await execFileAsync("which", ["pokeget"]);
        return true;
    }
    catch {
        return false;
    }
}
async function commandExists(cmd) {
    try {
        await execFileAsync("which", [cmd]);
        return true;
    }
    catch {
        return false;
    }
}
export async function getInstallInstructions() {
    const lines = [
        "pokeget is not installed. Pokebuddy needs it to render Pokémon sprites.",
        "",
    ];
    const platform = process.platform;
    const [hasCargo, hasBrew, hasYay, hasPacman, hasNix] = await Promise.all([
        commandExists("cargo"),
        commandExists("brew"),
        commandExists("yay"),
        commandExists("pacman"),
        commandExists("nix-env"),
    ]);
    // Build ordered list of options, best first for this platform
    const options = [];
    if (platform === "darwin") {
        if (hasBrew) {
            options.push("  brew install talwat/tap/pokeget     ← recommended (Homebrew)");
        }
        if (hasCargo) {
            options.push("  cargo install pokeget               ← works now (Rust already installed)");
        }
        else {
            options.push("  cargo install pokeget               (first: curl https://sh.rustup.rs | sh)");
        }
    }
    else if (platform === "linux") {
        if (hasYay) {
            options.push("  yay -S pokeget-rs                   ← recommended (AUR)");
        }
        else if (hasPacman) {
            options.push("  yay -S pokeget-rs                   (install yay first for AUR access)");
        }
        if (hasNix) {
            options.push("  nix-env -iA nixpkgs.pokeget         ← works now (Nix available)");
        }
        if (hasCargo) {
            options.push("  cargo install pokeget               ← works now (Rust already installed)");
        }
        else {
            options.push("  cargo install pokeget               (first: curl https://sh.rustup.rs | sh)");
        }
    }
    else {
        // Windows / other
        if (hasCargo) {
            options.push("  cargo install pokeget               ← works now (Rust already installed)");
        }
        else {
            options.push("  cargo install pokeget               (first: install Rust from https://rustup.rs)");
        }
    }
    if (options.length > 0) {
        lines.push("Install options:");
        lines.push(...options);
    }
    lines.push("");
    lines.push("Pokebuddy works in text-only mode until pokeget is installed.");
    return lines.join("\n");
}
// ---------------------------------------------------------------------------
// CLI interface — called from shell hooks:
//   node dist/sprites.js <species_or_id> [--shiny] [--hide-name]
//   node dist/sprites.js --check          (prints install instructions if missing)
// ---------------------------------------------------------------------------
const [, , pokemonArg, ...flags] = process.argv;
if (pokemonArg === "--check") {
    checkPokegetInstalled().then(async (installed) => {
        if (installed) {
            process.stdout.write("ok\n");
        }
        else {
            const instructions = await getInstallInstructions();
            process.stdout.write(instructions + "\n");
            process.exit(1);
        }
    });
}
else if (pokemonArg) {
    const shiny = flags.includes("--shiny");
    const hideName = flags.includes("--hide-name");
    getPokeSprite(pokemonArg, { shiny, hideName })
        .then((sprite) => process.stdout.write(sprite))
        .catch((err) => {
        process.stderr.write(String(err) + "\n");
        process.exit(1);
    });
}
//# sourceMappingURL=sprites.js.map