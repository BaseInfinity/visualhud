#!/usr/bin/env python3
"""Probe and compare the effective VisualHUD state of one iTerm2 session."""

import argparse
import json
import os
from pathlib import Path
import sys


PROFILE_TITLE_EXPRESSION = r"\(user.hudProgress)"


def color_components(color):
    """Return rounded 8-bit RGB components from an iTerm2 color."""
    if color is None:
        return None
    return [round(color.red), round(color.green), round(color.blue)]


def profile_property(profile, key, public_name=None):
    """Read an effective property missing from some iTerm2 SDK accessors."""
    if public_name and hasattr(profile, public_name):
        return getattr(profile, public_name)
    return getattr(profile, "_Profile__props", {}).get(key)


def compare_sample(expected, sample):
    """Return semantic mismatches for one effective iTerm2 sample."""
    mismatches = []
    progress = sample.get("hud_progress") or ""
    checkpoint = expected.get("checkpoint") or ""
    aggregate = expected.get("aggregate") or ""
    expected_sprite = expected.get("sprite") or ""

    if checkpoint and checkpoint not in progress:
        mismatches.append(f"hud_progress missing checkpoint: {checkpoint}")
    if aggregate and aggregate not in progress:
        mismatches.append(f"hud_progress missing aggregate: {aggregate}")
    if sample.get("use_custom_tab_title") not in (True, 1):
        mismatches.append("custom tab title is not enabled")
    if sample.get("custom_tab_title") != PROFILE_TITLE_EXPRESSION:
        mismatches.append("custom tab title is not bound to user.hudProgress")
    if sample.get("resolved_tab_title") != progress:
        mismatches.append("resolved tab title does not match hud_progress")
    if not sample.get("session_id"):
        mismatches.append("session_id is missing")
    if expected_sprite:
        actual_sprite = Path(sample.get("background_image_location") or "").name
        if actual_sprite != expected_sprite:
            mismatches.append(
                f"background sprite mismatch: expected {expected_sprite}, got {actual_sprite or '<empty>'}"
            )
    if expected.get("tab_color") != sample.get("tab_color"):
        mismatches.append(
            f"tab color mismatch: expected {expected.get('tab_color')}, got {sample.get('tab_color')}"
        )
    return mismatches


def compare(expected, samples):
    """Require two consecutive samples that both match and agree."""
    if len(samples) < 2:
        return ["at least two semantic samples are required"]

    recent = samples[-2:]
    mismatches = []
    for index, sample in enumerate(recent, start=1):
        mismatches.extend(
            f"sample {index}: {message}"
            for message in compare_sample(expected, sample)
        )

    convergence_fields = (
        "session_id",
        "hud_progress",
        "resolved_tab_title",
        "use_custom_tab_title",
        "custom_tab_title",
        "background_image_location",
        "tab_color",
    )
    for field in convergence_fields:
        if recent[0].get(field) != recent[1].get(field):
            mismatches.append(f"samples did not converge on {field}")
    if recent[0].get("session_name") == recent[1].get("session_name"):
        mismatches.append("host session name did not change between samples")
    return mismatches


def find_tab_and_session(app, session_id):
    """Find the exact iTerm2 tab/session without falling back to another pane."""
    target = session_id.split(":")[-1]
    for window in app.terminal_windows:
        for tab in window.tabs:
            for session in tab.sessions:
                if session.session_id == target:
                    return tab, session
    return None, None


def probe(session_id):
    """Read one effective profile/user-variable sample from iTerm2."""
    import iterm2

    sample = {}

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        tab, session = find_tab_and_session(app, session_id)
        if session is None:
            raise RuntimeError(f"iTerm2 session not found: {session_id}")
        profile = await session.async_get_profile()
        sample.update(
            {
                "session_id": session.session_id,
                "session_name": await session.async_get_variable("session.name"),
                "hud_progress": await session.async_get_variable("user.hudProgress"),
                "resolved_tab_title": await tab.async_get_variable("title"),
                "use_custom_tab_title": profile_property(
                    profile, "Use Custom Tab Title", "use_custom_tab_title"
                ),
                "custom_tab_title": profile_property(
                    profile, "Custom Tab Title", "custom_tab_title"
                ),
                "background_image_location": profile.background_image_location,
                "tab_color": color_components(profile.tab_color),
            }
        )

    iterm2.run_until_complete(main)
    return sample


def read_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    probe_parser = subparsers.add_parser("probe", help="read one real iTerm2 session sample")
    probe_parser.add_argument(
        "--session",
        default=os.environ.get("ITERM_SESSION_ID", ""),
        help="full ITERM_SESSION_ID or UUID (defaults to ITERM_SESSION_ID)",
    )

    compare_parser = subparsers.add_parser("compare", help="compare two semantic samples")
    compare_parser.add_argument("--expected", required=True)
    compare_parser.add_argument("--samples", required=True)
    return parser.parse_args()


def main():
    args = parse_args()
    if args.command == "probe":
        if not args.session:
            print("ITERM_SESSION_ID or --session is required", file=sys.stderr)
            return 2
        print(json.dumps(probe(args.session), indent=2))
        return 0

    mismatches = compare(read_json(args.expected), read_json(args.samples))
    if mismatches:
        for mismatch in mismatches:
            print(f"FAIL: {mismatch}", file=sys.stderr)
        return 1
    print("PASS: two consecutive iTerm2 semantic samples converged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
