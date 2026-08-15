#!/usr/bin/env python3
"""Set or clear an iTerm2 background image for the matching session."""

import sys

import iterm2


PROFILE_TITLE_EXPRESSION = r"\(user.hudProgress)"
TAB_TITLE_EXPRESSION = r"\(currentSession.user.hudProgress)"


async def find_tab_and_session_by_id(app, iterm_session_id):
    """Find the iTerm2 tab and session matching ITERM_SESSION_ID."""
    uuid = iterm_session_id.split(":")[-1] if ":" in iterm_session_id else iterm_session_id
    for window in app.terminal_windows:
        for tab in window.tabs:
            for session in tab.sessions:
                if session.session_id == uuid:
                    return tab, session
    return None, None


async def main(connection):
    image_path = sys.argv[1] if len(sys.argv) > 1 else ""
    session_id = sys.argv[2] if len(sys.argv) > 2 else None

    app = await iterm2.async_get_app(connection)
    target_tab, target_session = (
        await find_tab_and_session_by_id(app, session_id)
        if session_id
        else (None, None)
    )

    # No fallback: if session matching fails, do not mutate the wrong terminal.
    if not target_session:
        return

    change = iterm2.LocalWriteOnlyProfile(
        {
            "Use Custom Tab Title": True,
            "Custom Tab Title": PROFILE_TITLE_EXPRESSION,
        }
    )
    change.set_background_image_location(image_path)
    change.set_background_image_mode(iterm2.BackgroundImageMode.ASPECT_FIT)
    change.set_blend(0.15)
    await target_tab.async_set_title(TAB_TITLE_EXPRESSION)
    await target_session.async_set_profile_properties(change)


iterm2.run_until_complete(main)
