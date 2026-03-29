#!/usr/bin/env python3
"""Diagnose iTerm2 Python API — list all sessions and their IDs."""
import iterm2
import os
import sys

async def main(connection):
    env_id = os.environ.get("ITERM_SESSION_ID", "NOT SET")
    print(f"ITERM_SESSION_ID env var: {env_id}")
    print()

    app = await iterm2.async_get_app(connection)
    print("Sessions found by Python API:")
    for window in app.terminal_windows:
        for tab in window.tabs:
            for session in tab.sessions:
                match = " <-- MATCH" if session.session_id == env_id else ""
                print(f"  session_id: {session.session_id}{match}")

    print()
    if len(sys.argv) > 1:
        target = sys.argv[1]
        # ITERM_SESSION_ID is "w0t0p0:UUID" but API uses just "UUID"
        target_uuid = target.split(":")[-1] if ":" in target else target
        print(f"Searching for: {target} (uuid: {target_uuid})")
        for window in app.terminal_windows:
            for tab in window.tabs:
                for session in tab.sessions:
                    if session.session_id == target_uuid:
                        print("  FOUND — setting charmander background now...")
                        change = iterm2.LocalWriteOnlyProfile()
                        change.set_background_image_location(
                            os.path.expanduser("~/.claude/hooks/sprites/charmander.png")
                        )
                        change.set_background_image_mode(iterm2.BackgroundImageMode.ASPECT_FIT)
                        change.set_blend(0.15)
                        await session.async_set_profile_properties(change)
                        print("  DONE — check your background!")
                        return
        print("  NOT FOUND — no session matches that ID")

iterm2.run_until_complete(main)
