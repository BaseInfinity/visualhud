#!/bin/bash
# Badge diagnostic - test each layer independently
# Run in iTerm2: ./test-badge.sh

echo "=== Badge Diagnostic ==="
echo ""

# Test 1: Raw escape sequence (no Python API, no positioning)
echo "--- Test 1: Badge via escape sequence only ---"
echo "Setting badge to '🔥 TEST' via OSC 1337..."
printf '\033]1337;SetBadgeFormat=%s\a' "$(printf '%s' '🔥 TEST' | base64)"
echo "  Look for '🔥 TEST' in your terminal (default position: top-right)"
echo "  Do you see it? (Press Enter)"
read -r

# Test 2: Clear and re-set
echo "--- Test 2: Clear badge, then set again ---"
printf '\033]1337;SetBadgeFormat=\a'
echo "  Badge cleared. You should see nothing now. (Press Enter)"
read -r

printf '\033]1337;SetBadgeFormat=%s\a' "$(printf '%s' '💧 VISIBLE?' | base64)"
echo "  Set badge to '💧 VISIBLE?'. See it? (Press Enter)"
read -r

# Test 3: Check if Python API is reachable
echo "--- Test 3: iTerm2 Python API connection ---"
python3 -c "
import iterm2, asyncio
async def check(connection):
    app = await iterm2.async_get_app(connection)
    print('  Python API: CONNECTED')
    print(f'  Windows: {len(app.terminal_windows)}')
    for w in app.terminal_windows:
        for t in w.tabs:
            for s in t.sessions:
                print(f'  Session: {s.session_id}')
iterm2.run_until_complete(check)
" 2>&1
echo "(Press Enter)"
read -r

# Test 4: Check ITERM_SESSION_ID
echo "--- Test 4: Session ID ---"
echo "  ITERM_SESSION_ID=$ITERM_SESSION_ID"
if [ -z "$ITERM_SESSION_ID" ]; then
    echo "  WARNING: ITERM_SESSION_ID is empty - session matching will fail"
else
    echo "  UUID: $(echo "$ITERM_SESSION_ID" | cut -d: -f2)"
fi
echo "(Press Enter)"
read -r

# Test 5: Badge with Python API positioning (the suspected culprit)
echo "--- Test 5: Badge + Python API positioning ---"
echo "Setting badge via escape sequence AND positioning via Python API..."
printf '\033]1337;SetBadgeFormat=%s\a' "$(printf '%s' '⚡ POSITIONED' | base64)"
SESSION_ID="${ITERM_SESSION_ID:-}"
if [ -n "$SESSION_ID" ]; then
    python3 - "$SESSION_ID" <<'PYEOF' 2>&1
import iterm2, sys
async def main(connection):
    sid = sys.argv[1]
    uuid = sid.split(":")[-1] if ":" in sid else sid
    app = await iterm2.async_get_app(connection)
    for w in app.terminal_windows:
        for t in w.tabs:
            for s in t.sessions:
                if s.session_id == uuid:
                    grid = await s.async_get_screen_contents()
                    rows = grid.number_of_lines
                    cell_height = 16
                    window_height = rows * cell_height
                    top_margin = int(window_height * 0.85)
                    print(f"  Rows: {rows}")
                    print(f"  Estimated window height: {window_height}px")
                    print(f"  Setting badge_top_margin: {top_margin}px")
                    profile = await s.async_get_profile()
                    await profile.async_set_badge_top_margin(top_margin)
                    await profile.async_set_badge_right_margin(10)
                    print("  Badge positioned at bottom-right")
                    return
    print("  ERROR: Session not found")
iterm2.run_until_complete(main)
PYEOF
else
    echo "  SKIPPED: No ITERM_SESSION_ID"
fi
echo "  Do you see '⚡ POSITIONED' at bottom-right? (Press Enter)"
read -r

# Test 6: Reset badge positioning to defaults, keep badge text
echo "--- Test 6: Reset positioning to defaults ---"
if [ -n "$SESSION_ID" ]; then
    python3 - "$SESSION_ID" <<'PYEOF' 2>&1
import iterm2, sys
async def main(connection):
    sid = sys.argv[1]
    uuid = sid.split(":")[-1] if ":" in sid else sid
    app = await iterm2.async_get_app(connection)
    for w in app.terminal_windows:
        for t in w.tabs:
            for s in t.sessions:
                if s.session_id == uuid:
                    profile = await s.async_get_profile()
                    await profile.async_set_badge_top_margin(0)
                    await profile.async_set_badge_right_margin(0)
                    print("  Margins reset to 0 (default position: top-right)")
                    return
iterm2.run_until_complete(main)
PYEOF
fi
printf '\033]1337;SetBadgeFormat=%s\a' "$(printf '%s' '🌿 DEFAULT POS' | base64)"
echo "  Badge should now be in top-right with default sizing."
echo "  Do you see it NOW? (Press Enter)"
read -r

# Cleanup
echo "--- Cleanup ---"
printf '\033]1337;SetBadgeFormat=\a'
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
                    profile = await s.async_get_profile()
                    await profile.async_set_badge_top_margin(0)
                    await profile.async_set_badge_right_margin(0)
                    return
iterm2.run_until_complete(main)
PYEOF
fi
echo "Badge cleared. Done!"
echo ""
echo "=== Summary ==="
echo "If Test 1 failed: escape sequence issue (check iTerm2 version)"
echo "If Test 1 worked but Test 5 failed: Python API positioning is pushing badge off-screen"
echo "If Test 6 fixed it: confirmed - the custom margin math is the problem"
echo "If nothing worked: badge feature may be disabled in iTerm2 preferences"
