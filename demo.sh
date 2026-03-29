#!/bin/bash
# VisualHUD Feature Demo
# Run this in iTerm2 to see every visual feature we have.
# Usage: ./demo.sh

SPRITES_DIR="$HOME/.claude/hooks/sprites"
SET_BG="$HOME/.claude/hooks/set_bg.py"
SESSION_ID="${ITERM_SESSION_ID:-}"

echo "=== VisualHUD Feature Demo ==="
echo "Session ID: $SESSION_ID"
echo ""

pause() {
    echo ""
    echo "  Press Enter to continue..."
    read -r
}

set_colors() {
    local r="$1" g="$2" b="$3"
    local rh gh bh tr tg tb
    rh=$(printf '%02x' "$r")
    gh=$(printf '%02x' "$g")
    bh=$(printf '%02x' "$b")
    tr=$(printf '%02x' $(( r * 3 / 10 )))
    tg=$(printf '%02x' $(( g * 3 / 10 )))
    tb=$(printf '%02x' $(( b * 3 / 10 )))

    # Background tint
    printf '\033]1337;SetColors=bg=%s%s%s\a' "$tr" "$tg" "$tb"
    # Tab color (border)
    printf '\033]6;1;bg;red;brightness;%d\a' "$r"
    printf '\033]6;1;bg;green;brightness;%d\a' "$g"
    printf '\033]6;1;bg;blue;brightness;%d\a' "$b"
    # Cursor color (iTerm2 native)
    printf '\033]1337;SetColors=curbg=%s%s%s\a' "$rh" "$gh" "$bh"
}

set_badge() {
    printf '\033]1337;SetBadgeFormat=%s\a' "$(printf '%s' "$1" | base64)"
}

progress_bar() {
    # Colored squares: fire 🟥 → electric 🟨 → grass 🟩 → water 🟦
    local stage="$1" i
    local colors=("🟥" "🟥" "🟧" "🟨" "🟨" "🟩" "🟩" "🟩" "🟦" "🟦" "🟦")
    local bar=""
    for ((i=0; i<stage && i<11; i++)); do
        bar="${bar}${colors[$i]}"
    done
    printf '%s' "$bar"
}

set_bg_image() {
    local image="$1"
    if [ -f "$SET_BG" ] && [ -n "$SESSION_ID" ]; then
        python3 "$SET_BG" "$image" "$SESSION_ID" 2>/dev/null
    else
        echo "  (skipped — no SESSION_ID or set_bg.py)"
    fi
}

clear_bg_image() {
    if [ -n "$SESSION_ID" ]; then
        python3 - "$SESSION_ID" <<'PYEOF' 2>/dev/null
import iterm2, sys
async def main(connection):
    sid = sys.argv[1]
    uuid = sid.split(":")[-1] if ":" in sid else sid
    app = await iterm2.async_get_app(connection)
    for w in app.terminal_windows:
        for t in w.tabs:
            for s in t.sessions:
                if s.session_id == uuid:
                    change = iterm2.LocalWriteOnlyProfile()
                    change.set_background_image_location("")
                    await s.async_set_profile_properties(change)
                    return
iterm2.run_until_complete(main)
PYEOF
    fi
}

# ============================================================
echo "--- TEST 1: Full Loading Bar (logarithmic scaling) ---"
echo "Loading bar fills from red → orange → yellow → green → blue"
echo "Each stage represents a logarithmic range of tool calls."
echo ""
echo "  NEW scaling (vs old 3-per-stage):"
echo "  Stage 1-2:   1-2 calls     (was 1-3)"
echo "  Stage 3:     6-12 calls    (was 7-9)"
echo "  Stage 6:     46-75 calls   (was 16-18)"
echo "  Stage 10:    281-400 calls (was 28-30)"
echo ""

stages=(
    "charmander|255 60 60|🔥 Charmander|🔥|1|Charmander|1-2 calls"
    "charmeleon|255 100 50|🔥 Charmeleon|🔥|2|Charmeleon|3-5 calls"
    "charizard|255 150 40|🔥 Charizard|🔥|3|Charizard|6-12 calls"
    "pikachu|250 210 50|⚡ Pikachu|⚡|4|Pikachu|13-25 calls"
    "raichu|230 180 40|⚡ Raichu|⚡|5|Raichu|26-45 calls"
    "bulbasaur|130 200 60|🌿 Bulbasaur|🌿|6|Bulbasaur|46-75 calls"
    "ivysaur|80 180 70|🌿 Ivysaur|🌿|7|Ivysaur|76-120 calls"
    "venusaur|60 170 80|🌿 Venusaur|🌿|8|Venusaur|121-180 calls"
    "squirtle|70 160 230|💧 Squirtle|💧|9|Squirtle|181-280 calls"
    "wartortle|50 130 240|💧 Wartortle|💧|10|Wartortle|281-400 calls"
    "blastoise|40 100 255|💧 Blastoise (Done)|💧|11|Your turn|Stop event"
)

for entry in "${stages[@]}"; do
    IFS='|' read -r sprite colors name badge stage_num stage_name range <<< "$entry"
    IFS=' ' read -r r g b <<< "$colors"
    set_colors "$r" "$g" "$b"
    badge_text="${badge} $(progress_bar "$stage_num") ${stage_name}"
    set_badge "$badge_text"
    printf '\033]0;%s %s — %s\a' "$(progress_bar "$stage_num")" "$name" "$(basename "$PWD")"
    if [ -f "${SPRITES_DIR}/${sprite}.png" ]; then
        set_bg_image "${SPRITES_DIR}/${sprite}.png"
    fi
    echo "  $name  ${badge}  $(progress_bar "$stage_num")  [rgb($r,$g,$b)]  $range"
    sleep 2
done

pause

# ============================================================
echo "--- TEST 2: BLOCKED State (Snorlax blocks the path!) ---"
echo "This is what you see when Claude needs your permission."
echo "Terminal goes DARK — Snorlax blocks progress. Stands out from colorful working states."
echo ""

set_colors 40 40 50
set_badge "😴 BLOCKED"
printf '\033]0;😴 BLOCKED — %s\a' "$(basename "$PWD")"
if [ -f "${SPRITES_DIR}/snorlax.png" ]; then
    set_bg_image "${SPRITES_DIR}/snorlax.png"
fi
echo "  😴 BLOCKED — dark terminal, Snorlax sprite, muted colors"
echo "  (In real use, this fires from the Notification hook)"

pause

# ============================================================
echo "--- TEST 3: ERROR State (API Failure) ---"
echo "This is what you see when Claude hits a rate limit or API error."
echo ""

set_colors 255 40 40
set_badge "⚠️ ERROR"
printf '\033]0;⚠️ Error — %s\a' "$(basename "$PWD")"
echo "  ⚠️ ERROR — red tab, error badge"
echo "  (In real use, this fires from the StopFailure hook)"

pause

# ============================================================
echo "--- TEST 4: Done State ---"
echo "Full 'done' state: blue + Blastoise + Your turn badge"
echo ""

set_colors 40 100 255
set_badge "💧 ███████████ Your turn"
printf '\033]0;%s 💧 Done — %s\a' "$(progress_bar 11)" "$(basename "$PWD")"
set_bg_image "${SPRITES_DIR}/blastoise.png"
echo "  💧 Done — your turn to act!"

pause

# ============================================================
echo "--- CLEANUP ---"
echo "Resetting terminal to defaults..."

# Clear badge
printf '\033]1337;SetBadgeFormat=\a'
# Reset tab color
printf '\033]6;1;bg;*;default\a'
# Reset background color
printf '\033]1337;SetColors=bg=default\a'
# Reset cursor
printf '\033]1337;SetColors=curbg=default\a'
# Clear title
printf '\033]0;%s\a' ""
# Clear background image
clear_bg_image

echo "  Done! Terminal should be back to normal."
echo ""
echo "=== Demo Complete ==="
