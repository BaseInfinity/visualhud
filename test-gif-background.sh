#!/bin/bash
# Test 1: Can iTerm2 animate a GIF as a background image?
# Run this in iTerm2 to see if the background actually animates or just shows frame 1.

SPRITES_DIR="$HOME/.claude/hooks/sprites"
GIF="$SPRITES_DIR/charmander.gif"

echo "Setting charmander.gif as background via Python API..."
echo "Watch the background — if Charmander moves, GIFs work natively."
echo "If it's frozen, we need frame cycling."
echo ""

python3 - "$GIF" <<'PYEOF'
import iterm2, sys

async def main(connection):
    app = await iterm2.async_get_app(connection)
    session = app.current_terminal_window.current_tab.current_session

    change = iterm2.LocalWriteOnlyProfile()
    change.set_background_image_location(sys.argv[1])
    change.set_background_image_mode(iterm2.BackgroundImageMode.ASPECT_FIT)
    change.set_blend(0.15)
    await session.async_set_profile_properties(change)
    print("Background set. Is it animating? (y/n)")

iterm2.run_until_complete(main)
PYEOF

read -r answer
if [ "$answer" = "y" ]; then
    echo "GIF backgrounds work natively! No frame cycling needed."
else
    echo "GIF backgrounds are static. Frame cycling required for animation."
fi
