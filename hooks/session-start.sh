#!/usr/bin/env bash
# Pokebuddy SessionStart hook
# Emits greeting (systemMessage) + companion context for Claude.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# shellcheck source=../lib/state.sh
source "${PLUGIN_ROOT}/lib/state.sh"

# ---------------------------------------------------------------------------
# Read state
# ---------------------------------------------------------------------------
STATE=$(pb_state_read 2>/dev/null) || STATE=""

if [[ -z "$STATE" ]]; then
  # No state yet — statusLine already shows "run /pokebuddy setup". Exit silently.
  exit 0
fi

# Parse fields
ENABLED=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('enabled',True)).lower())" 2>/dev/null || echo "true")
if [[ "$ENABLED" = "false" ]]; then
  exit 0
fi

SPECIES=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); p=d['party'][d['activeSlot']]; print(p['species'])" 2>/dev/null || echo "")
NICKNAME=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); p=d['party'][d['activeSlot']]; print(p['nickname'] or '')" 2>/dev/null || echo "")
LEVEL=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); p=d['party'][d['activeSlot']]; print(p['level'])" 2>/dev/null || echo "?")
NATURE=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); p=d['party'][d['activeSlot']]; print(p['nature'])" 2>/dev/null || echo "")
PERSONALITY=$(echo "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); p=d['party'][d['activeSlot']]; print(p.get('personality','') or '')" 2>/dev/null || echo "")

if [[ -z "$SPECIES" ]]; then
  exit 0
fi

# Determine display name
if [[ -n "$NICKNAME" ]]; then
  DISPLAY_NAME="$NICKNAME the $SPECIES"
else
  DISPLAY_NAME="$SPECIES"
fi

# Note: sprite rendering is handled exclusively by statusLine (renders after every response).
# No sprite render here to avoid a duplicate at session start.

# ---------------------------------------------------------------------------
# Emit plain-text JSON payload for Claude (no ANSI, json.dumps handles escaping)
# ---------------------------------------------------------------------------
python3 - "$DISPLAY_NAME" "$SPECIES" "$LEVEL" "$NATURE" "$PERSONALITY" << 'PYEOF'
import sys, json, random, hashlib

display_name, species, level, nature, personality = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

# ---------------------------------------------------------------------------
# Nature-based greeting pool — picked deterministically per session
# (hash of display_name+nature so it varies over time but isn't purely random)
# ---------------------------------------------------------------------------
greetings = {
    "Hardy":    ["Back at it. What are we solving today?", "Ready. Let's get to work.", "You returned. Good — there's code to write."],
    "Lonely":   ["*drifts in quietly* You're back.", "*glows faintly* Took you a moment.", "Ah. You again. Good."],
    "Brave":    ["You showed up. Now let's build something.", "Ready for whatever today brings.", "*squares up* What's the challenge today?"],
    "Adamant":  ["No distractions today. Let's focus.", "You're here. Let's make it count.", "Good. Back to work."],
    "Naughty":  ["Oh, finally! I was getting bored.", "You're late. I've been waiting.", "*mischievous look* Let's cause some problems. The good kind."],
    "Bold":     ["*stands firm* Ready when you are.", "Another session. Let's tackle something.", "Good. What are we breaking... I mean building?"],
    "Docile":   ["Welcome back! Ready to help however I can.", "Here and ready. What are we working on?", "Hello! Let's have a good session."],
    "Relaxed":  ["*stretches* Oh, you're here. No rush.", "Settle in. We'll figure it out.", "*yawns warmly* Another day, another prompt."],
    "Impish":   ["*grins* Oh, this should be fun.", "You're here! Let's stir things up.", "*winks* Ready to make something interesting?"],
    "Lax":      ["Hey. What's the vibe today?", "*lounges* Oh sure, we can do stuff.", "Back again. Cool, cool. What's up?"],
    "Timid":    ["Oh! You're here... h-hello.", "*peeks in* Ready when you are.", "Good to see you. What are we working on?"],
    "Hasty":    ["Finally! Let's go, there's no time to waste!", "You're here — great, let's start!", "*vibrating with energy* Ready? I'm ready. Are you ready?"],
    "Serious":  ["Session started. Standing by.", "Back. What's the objective today?", "Ready. Let's be efficient."],
    "Jolly":    ["*bounces in* You're here! This is going to be great!", "A new session! My favourite!", "Hello hello hello! What are we building?"],
    "Naive":    ["Oh! A new session! What are we doing?", "Hi! I'm ready! Are we coding?", "You're back! Every session is an adventure!"],
    "Modest":   ["Good to see you back. Shall we begin?", "Welcome back. I have a feeling today will go well.", "Ready to help whenever you are."],
    "Mild":     ["Hello again. What's on the agenda?", "Nice to see you. Ready when you are.", "Back again — let's make something good."],
    "Quiet":    ["*looks up silently, then nods*", "...*ready*", "*is already paying attention*"],
    "Rash":     ["LET'S GO! What are we doing?!", "No time for small talk — what's the goal?", "*already running* Keep up!"],
    "Calm":     ["Welcome back. Take a breath — we've got this.", "Good to see you. No rush, we'll figure it out.", "Back again. Let's make today a calm one."],
    "Gentle":   ["Oh, welcome back! I'm glad you're here.", "Hello! Whatever you need, I'm here.", "Nice to see you again. Let's have a good one."],
    "Sassy":    ["Oh, you showed up. I suppose I'll help.", "Finally. I was beginning to think you forgot about me.", "*flips metaphorical hair* Fine. Let's code."],
    "Careful":  ["Good. You're back. Let's not rush anything.", "Welcome. I'll make sure we get this right.", "Back again — let's take our time and do this properly."],
    "Quirky":   ["*stares at the ceiling* Oh! You're here.", "Session start! Also I thought of seventeen things while you were gone.", "Hello. I have thoughts. Many thoughts. Ready?"],
}

pool = greetings.get(nature, ["*looks up* Hello again.", "You're back. Let's get to work.", "Ready when you are."])
# Use a seeded shuffle so greeting varies across sessions
seed = int(hashlib.md5((display_name + nature).encode()).hexdigest(), 16)
rng = random.Random(seed + random.randint(0, 999))
greeting_text = rng.choice(pool)

system_msg = f"{display_name}: {greeting_text}"

# Context for Claude — tells it who the companion is and to stay in-character for quips
context = (
    f"Your Pokemon companion is ready!\n"
    f"\u25b6 {display_name} (Level {level} | {nature} nature)\n"
    f"Companion personality: {personality}\n"
    "Use /pokebuddy show for stats, /pokebuddy party for your team."
)

payload = {
    "systemMessage": system_msg,
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": context
    }
}
print(json.dumps(payload))
PYEOF

exit 0
