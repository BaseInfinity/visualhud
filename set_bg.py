#!/usr/bin/env python3
"""Set or clear an iTerm2 background image for the matching session."""

import hashlib
import os
from pathlib import Path
import subprocess
import sys

import iterm2


PROFILE_TITLE_EXPRESSION = r"\(user.hudProgress)"
TAB_TITLE_EXPRESSION = r"\(currentSession.user.hudProgress)"
MAX_CONTEXT_PNG_BYTES = 67_108_864


def _hash_file(digest, path):
    with Path(path).open("rb") as handle:
        while True:
            block = handle.read(1024 * 1024)
            if not block:
                return
            digest.update(block)


def context_composite_path(image_path, context_path, context_color, state_root):
    """Return a cached deterministic composite, falling back to the primary art."""
    if not image_path or not context_path or not context_color:
        return image_path

    compositor = Path(__file__).resolve().parent / "scripts" / "visualhud_context_overlay.py"
    if not compositor.is_file() or not Path(image_path).is_file() or not Path(context_path).is_file():
        return image_path
    if (Path(image_path).stat().st_size > MAX_CONTEXT_PNG_BYTES
            or Path(context_path).stat().st_size > MAX_CONTEXT_PNG_BYTES):
        return image_path

    digest = hashlib.sha256()
    digest.update(b"visualhud-context-overlay-v1\0")
    _hash_file(digest, image_path)
    _hash_file(digest, context_path)
    digest.update(context_color.encode("ascii"))
    cache_root = Path(state_root or os.environ.get("TMPDIR", "/tmp"))
    output = cache_root / f"visualhud-context-overlay-{digest.hexdigest()}.png"
    if not output.is_file():
        result = subprocess.run(
            [sys.executable, str(compositor), image_path, context_path, context_color, str(output)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode != 0 or not output.is_file():
            return image_path
    return str(output)


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
    context_path = sys.argv[3] if len(sys.argv) > 3 else ""
    context_color = sys.argv[4] if len(sys.argv) > 4 else ""
    state_root = sys.argv[5] if len(sys.argv) > 5 else ""
    image_path = context_composite_path(image_path, context_path, context_color, state_root)

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
