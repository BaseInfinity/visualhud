#!/bin/bash
# VisualHUD - iTerm2 Settings Setup
# Configures all required iTerm2 settings programmatically.
#
# Usage: ./setup-iterm2.sh
#
# NOTE: iTerm2 must be QUIT before running this for defaults write to stick.
# After running, reopen iTerm2.

set -e

echo "=== VisualHUD iTerm2 Setup ==="
echo ""

# Check if iTerm2 is running
if pgrep -x "iTerm2" > /dev/null 2>&1; then
    echo "WARNING: iTerm2 is currently running."
    echo "For settings to stick, you should:"
    echo "  1. Quit iTerm2 (Cmd+Q)"
    echo "  2. Run this script from Terminal.app"
    echo "  3. Reopen iTerm2"
    echo ""
    read -rp "Continue anyway? (y/n) " confirm
    if [ "$confirm" != "y" ]; then
        echo "Aborted. Quit iTerm2 first, then re-run."
        exit 1
    fi
fi

echo "--- Appearance Settings (defaults write) ---"

# Show tab bar even when there is only one tab
# HideTab=false means "show tab bar"
defaults write com.googlecode.iterm2 HideTab -bool false
echo "  [x] Show tab bar even when there is only one tab"

# Tab bar position: bottom (1) — gives the colored tab a hero banner / footer feel
# 0=Top, 1=Bottom, 2=Left
defaults write com.googlecode.iterm2 TabViewType -int 1
echo "  [x] Tab bar at bottom (hero banner footer)"

# Theme: Minimal (5) for most dramatic tab colors
# 0=Light, 1=Dark, 2=Light HC, 3=Dark HC, 4=Automatic, 5=Minimal, 6=Compact
defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 5
echo "  [x] Theme: Minimal (tab color fills entire title bar)"

# Enable Python API (required for background images + badge)
defaults write com.googlecode.iterm2 EnableAPIServer -bool true
echo "  [x] Enable Python API"

# Separate background images per pane
defaults write com.googlecode.iterm2 PerPaneBackgroundImage -bool true
echo "  [x] Separate background images per pane"

# Dimming affects only text (keeps sprites visible in unfocused windows)
defaults write com.googlecode.iterm2 DimOnlyText -bool true
echo "  [x] Dimming affects only text, not background"

# Show per-pane title bar when using split panes (each pane shows its own progress)
defaults write com.googlecode.iterm2 ShowPaneTitles -bool true
echo "  [x] Show per-pane title bar with split panes"

echo ""
echo "--- Dynamic Profile (badge + cursor settings) ---"

# Create Dynamic Profile with badge and cursor settings
DYNAMIC_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
mkdir -p "$DYNAMIC_DIR"

cat > "$DYNAMIC_DIR/visualhud-profile.json" << 'DYNEOF'
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
echo "  [x] Badge position: top-right (margin 0)"
echo "  [x] Dynamic profile written to: $DYNAMIC_DIR/visualhud-profile.json"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Quit iTerm2 (Cmd+Q) if it's still running"
echo "  2. Reopen iTerm2"
echo "  3. Run ./demo.sh to verify everything works"
echo ""
echo "What this changed:"
echo "  - Tab bar always visible (you'll see tab colors now)"
echo "  - Minimal theme (tab colors fill the title bar)"
echo "  - Python API enabled (background sprites work)"
echo "  - Badge at top-right with no margin hacks"
echo "  - Smart cursor color OFF (escape sequences control cursor)"
echo ""
echo "To undo: ./setup-iterm2.sh --reset"
if [ "${1:-}" = "--reset" ]; then
    echo "--- Resetting to defaults ---"
    defaults write com.googlecode.iterm2 HideTab -bool true
    defaults delete com.googlecode.iterm2 TabViewType 2>/dev/null || true
    defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 4
    defaults delete com.googlecode.iterm2 EnableAPIServer 2>/dev/null || true
    defaults delete com.googlecode.iterm2 PerPaneBackgroundImage 2>/dev/null || true
    defaults delete com.googlecode.iterm2 DimOnlyText 2>/dev/null || true
    defaults delete com.googlecode.iterm2 ShowPaneTitles 2>/dev/null || true
    rm -f "$DYNAMIC_DIR/visualhud-profile.json"
    echo "  Done. Restart iTerm2."
    exit 0
fi
