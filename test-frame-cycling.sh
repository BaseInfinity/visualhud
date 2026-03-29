#!/bin/bash
# Test 2: Cycle extracted frames as background images.
# Tests if rapidly swapping PNGs creates smooth animation without flicker.

FRAMES_DIR="/private/tmp/claude-501/sprite-test"
FRAME_DELAY_MS=30  # Match the GIF's 30ms frame timing

# Check if frames exist
if [ ! -f "$FRAMES_DIR/charmander_000.png" ]; then
    echo "No extracted frames found. Run this first:"
    echo "  python3 -c \"from PIL import Image; ...\"  (see README)"
    exit 1
fi

FRAME_COUNT=$(ls "$FRAMES_DIR"/charmander_*.png 2>/dev/null | wc -l | tr -d ' ')
echo "Cycling $FRAME_COUNT frames at ${FRAME_DELAY_MS}ms intervals..."
echo "Press Ctrl+C to stop."
echo ""

# Convert ms to seconds for sleep
SLEEP_TIME=$(python3 -c "print($FRAME_DELAY_MS / 1000)")

python3 - "$FRAMES_DIR" "$FRAME_COUNT" "$SLEEP_TIME" <<'PYEOF'
import iterm2
import sys
import asyncio

async def main(connection):
    frames_dir = sys.argv[1]
    frame_count = int(sys.argv[2])
    sleep_time = float(sys.argv[3])

    app = await iterm2.async_get_app(connection)
    session = app.current_terminal_window.current_tab.current_session

    print(f"Starting animation loop: {frame_count} frames, {sleep_time}s per frame")
    try:
        cycle = 0
        while True:
            for i in range(frame_count):
                path = f"{frames_dir}/charmander_{i:03d}.png"
                change = iterm2.LocalWriteOnlyProfile()
                change.set_background_image_location(path)
                change.set_background_image_mode(iterm2.BackgroundImageMode.ASPECT_FIT)
                change.set_blend(0.15)
                await session.async_set_profile_properties(change)
                await asyncio.sleep(sleep_time)
            cycle += 1
            if cycle == 1:
                print("First cycle complete. How does it look? Smooth or flickery?")
    except KeyboardInterrupt:
        print("\nStopped. Clearing background...")
        change = iterm2.LocalWriteOnlyProfile()
        change.set_background_image_location("")
        await session.async_set_profile_properties(change)

iterm2.run_until_complete(main)
PYEOF
