#!/usr/bin/env python3
"""Set or clear an iTerm2 background image for the matching session."""

import sys

import iterm2


async def find_session_by_id(app, iterm_session_id):
    """Find the iTerm2 session matching the ITERM_SESSION_ID env var."""
    uuid = iterm_session_id.split(":")[-1] if ":" in iterm_session_id else iterm_session_id
    for window in app.terminal_windows:
        for tab in window.tabs:
            for session in tab.sessions:
                if session.session_id == uuid:
                    return session
    return None


async def main(connection):
    image_path = sys.argv[1] if len(sys.argv) > 1 else ""
    session_id = sys.argv[2] if len(sys.argv) > 2 else None

    app = await iterm2.async_get_app(connection)
    target_session = await find_session_by_id(app, session_id) if session_id else None

    # No fallback: if session matching fails, do not mutate the wrong terminal.
    if not target_session:
        return

    change = iterm2.LocalWriteOnlyProfile()
    change.set_background_image_location(image_path)
    change.set_background_image_mode(iterm2.BackgroundImageMode.ASPECT_FIT)
    change.set_blend(0.15)
    await target_session.async_set_profile_properties(change)


iterm2.run_until_complete(main)
