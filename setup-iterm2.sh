#!/bin/bash
# VisualHUD - iTerm2 Settings Setup
# Applies required iTerm2 settings without interrupting active terminal work.

set -Eeuo pipefail

DYNAMIC_DIR="${VISUALHUD_ITERM2_DYNAMIC_DIR:-$HOME/Library/Application Support/iTerm2/DynamicProfiles}"

setup_failed() {
    local status=$?
    printf '[blocked] iTerm2 settings could not be written (exit %s).\n' "$status" >&2
    exit "$status"
}
trap setup_failed ERR

reset_iterm2() {
    echo "=== VisualHUD iTerm2 Reset ==="
    defaults write com.googlecode.iterm2 HideTab -bool true
    defaults delete com.googlecode.iterm2 TabViewType 2>/dev/null || true
    defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 4
    defaults delete com.googlecode.iterm2 EnableAPIServer 2>/dev/null || true
    defaults delete com.googlecode.iterm2 PerPaneBackgroundImage 2>/dev/null || true
    defaults delete com.googlecode.iterm2 DimOnlyText 2>/dev/null || true
    defaults delete com.googlecode.iterm2 ShowPaneTitles 2>/dev/null || true
    rm -f "$DYNAMIC_DIR/visualhud-profile.json"
    echo "  [ok] VisualHUD iTerm2 settings reset"
    echo "  [pending] Restart iTerm2 later to refresh terminal visuals"
}

case "${1:-}" in
    --reset)
        reset_iterm2
        exit 0
        ;;
    "")
        ;;
    *)
        printf 'Usage: %s [--reset]\n' "$0" >&2
        exit 2
        ;;
esac

iterm_state=not-running
if [ -n "${ITERM_SESSION_ID:-}" ] || [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
    iterm_state=running
elif command -v pgrep >/dev/null 2>&1; then
    if pgrep -x "iTerm2" >/dev/null 2>&1; then
        iterm_state=running
    else
        pgrep_status=$?
        if [ "$pgrep_status" -gt 1 ]; then
            iterm_state=unknown
        fi
    fi
else
    iterm_state=unknown
fi

echo "=== VisualHUD iTerm2 Setup ==="
echo ""
echo "--- Appearance Settings (defaults write) ---"

defaults write com.googlecode.iterm2 HideTab -bool false
echo "  [x] Show tab bar even when there is only one tab"

defaults write com.googlecode.iterm2 TabViewType -int 1
echo "  [x] Tab bar at bottom (hero banner footer)"

defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 5
echo "  [x] Theme: Minimal (tab color fills the entire title bar)"

defaults write com.googlecode.iterm2 EnableAPIServer -bool true
echo "  [x] Enable Python API"

defaults write com.googlecode.iterm2 PerPaneBackgroundImage -bool true
echo "  [x] Separate background images per pane"

defaults write com.googlecode.iterm2 DimOnlyText -bool true
echo "  [x] Dimming affects only text, not background"

defaults write com.googlecode.iterm2 ShowPaneTitles -bool true
echo "  [x] Show per-pane title bar with split panes"

echo ""
echo "--- Dynamic Profile (badge + cursor settings) ---"
mkdir -p "$DYNAMIC_DIR"

cat > "$DYNAMIC_DIR/visualhud-profile.json" <<'DYNEOF'
{
  "Profiles": [{
    "Name": "Default",
    "Guid": "Default",
    "Dynamic Profile Parent Name": "Default",
    "Smart Cursor Color": false,
    "Badge Color": {
      "Red Component": 1.0,
      "Green Component": 1.0,
      "Blue Component": 1.0,
      "Alpha Component": 0.3
    },
    "Badge Top Margin": 0,
    "Badge Right Margin": 10,
    "Badge Max Width": 50,
    "Badge Max Height": 20,
    "Custom Tab Title": "\\(user.hudProgress)",
    "Tab Title": 2
  }]
}
DYNEOF

echo "  [x] Smart Cursor Color: OFF"
echo "  [x] Badge color: white, 30% alpha"
echo "  [x] Badge position: top-right"
echo "  [x] Dynamic profile written to: $DYNAMIC_DIR/visualhud-profile.json"
echo ""
echo "=== Setup Complete ==="
case "$iterm_state" in
    running)
        echo "  [pending] iTerm2 restart later to refresh terminal visuals; keep working now"
        ;;
    unknown)
        echo "  [pending] iTerm2 process status unavailable; restart later if visuals are stale"
        ;;
    *)
        echo "  [ok] iTerm2 restart not currently required"
        ;;
esac
echo "To undo: $0 --reset"
