#!/bin/bash
# VisualHUD - iTerm2 Settings Setup
# Applies required iTerm2 settings without interrupting active terminal work.

set -Eeuo pipefail

DYNAMIC_DIR="${VISUALHUD_ITERM2_DYNAMIC_DIR:-$HOME/Library/Application Support/iTerm2/DynamicProfiles}"
STATUS_FILE="${VISUALHUD_SETUP_STATUS_FILE:-}"

write_status() {
    [ -n "$STATUS_FILE" ] || return 0
    mkdir -p "$(dirname "$STATUS_FILE")"
    printf '%s\n' "$1" > "$STATUS_FILE"
}

profile_json() {
    cat <<'DYNEOF'
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
}

preference_matches() {
    local key="$1" expected="$2" actual
    actual=$(defaults read com.googlecode.iterm2 "$key" 2>/dev/null) || return 1
    [ "$actual" = "$expected" ]
}

preference_missing() {
    ! defaults read com.googlecode.iterm2 "$1" >/dev/null 2>&1
}

profile_matches() {
    [ -f "$DYNAMIC_DIR/visualhud-profile.json" ] && \
        cmp -s "$DYNAMIC_DIR/visualhud-profile.json" <(profile_json)
}

setup_failed() {
    local status=$?
    write_status "blocked:$status" || true
    printf '[blocked] iTerm2 settings could not be written (exit %s).\n' "$status" >&2
    exit "$status"
}
trap setup_failed ERR

read_status() {
    [ -n "$STATUS_FILE" ] && cat "$STATUS_FILE" 2>/dev/null || true
}

detect_iterm_state() {
    local probe_output probe_status
    iterm_state=not-running
    iterm_pid=""
    if command -v pgrep >/dev/null 2>&1; then
        if probe_output=$(pgrep -x "iTerm2" 2>/dev/null); then
            iterm_state=running
            iterm_pid=$(printf '%s\n' "$probe_output" | head -n 1)
        else
            probe_status=$?
            if [ "$probe_status" -gt 1 ]; then
                iterm_state=unknown
            fi
        fi
    else
        iterm_state=unknown
    fi
    if [ -n "${ITERM_SESSION_ID:-}" ] || [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
        iterm_state=running
    fi
}

record_changed_restart_state() {
    detect_iterm_state
    case "$iterm_state" in
        running)
            if [ -n "$iterm_pid" ]; then
                write_status "restart-required:$iterm_pid"
            else
                write_status "restart-required"
            fi
            echo "  [pending] iTerm2 restart later to refresh terminal visuals; keep working now"
            ;;
        unknown)
            write_status "restart-unknown"
            echo "  [pending] iTerm2 process status unavailable; restart later if visuals are stale"
            ;;
        *)
            write_status "ready"
            echo "  [ok] iTerm2 restart not currently required"
            ;;
    esac
}

report_unchanged_restart_state() {
    local previous expected_pid
    previous=$(read_status)
    case "$previous" in
        restart-required:*)
            expected_pid=${previous#restart-required:}
            detect_iterm_state
            if [ "$iterm_state" = "not-running" ] || { [ -n "$iterm_pid" ] && [ "$iterm_pid" != "$expected_pid" ]; }; then
                write_status "ready"
                echo "  [ok] iTerm2 preferences already current; terminal restart not required"
            else
                write_status "$previous"
                echo "  [ok] iTerm2 preferences already current"
                echo "  [pending] iTerm2 restart later to refresh terminal visuals; keep working now"
            fi
            ;;
        restart-required)
            detect_iterm_state
            if [ "$iterm_state" = "not-running" ]; then
                write_status "ready"
                echo "  [ok] iTerm2 preferences already current; terminal restart not required"
            else
                write_status "$previous"
                echo "  [ok] iTerm2 preferences already current"
                echo "  [pending] iTerm2 restart later to refresh terminal visuals; keep working now"
            fi
            ;;
        restart-unknown)
            detect_iterm_state
            if [ "$iterm_state" = "not-running" ]; then
                write_status "ready"
                echo "  [ok] iTerm2 preferences already current; terminal restart not required"
            else
                write_status "$previous"
                echo "  [ok] iTerm2 preferences already current"
                echo "  [pending] iTerm2 process status unavailable; restart later if visuals are stale"
            fi
            ;;
        *)
            write_status "ready"
            echo "  [ok] iTerm2 preferences already current; terminal restart not required"
            ;;
    esac
}

reset_iterm2() {
    local reset_changed=false
    preference_matches HideTab 1 || reset_changed=true
    preference_missing TabViewType || reset_changed=true
    preference_matches TabStyleWithAutomaticOption 4 || reset_changed=true
    preference_missing EnableAPIServer || reset_changed=true
    preference_missing PerPaneBackgroundImage || reset_changed=true
    preference_missing DimOnlyText || reset_changed=true
    preference_missing ShowPaneTitles || reset_changed=true
    [ ! -e "$DYNAMIC_DIR/visualhud-profile.json" ] || reset_changed=true
    echo "=== VisualHUD iTerm2 Reset ==="
    if [ "$reset_changed" = true ]; then
        defaults write com.googlecode.iterm2 HideTab -bool true
        defaults delete com.googlecode.iterm2 TabViewType 2>/dev/null || true
        defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 4
        defaults delete com.googlecode.iterm2 EnableAPIServer 2>/dev/null || true
        defaults delete com.googlecode.iterm2 PerPaneBackgroundImage 2>/dev/null || true
        defaults delete com.googlecode.iterm2 DimOnlyText 2>/dev/null || true
        defaults delete com.googlecode.iterm2 ShowPaneTitles 2>/dev/null || true
        rm -f "$DYNAMIC_DIR/visualhud-profile.json"
    fi
    echo "  [ok] VisualHUD iTerm2 settings reset"
    if [ "$reset_changed" = true ]; then
        record_changed_restart_state
    else
        report_unchanged_restart_state
    fi
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

settings_changed=false
preference_matches HideTab 0 || settings_changed=true
preference_matches TabViewType 1 || settings_changed=true
preference_matches TabStyleWithAutomaticOption 5 || settings_changed=true
preference_matches EnableAPIServer 1 || settings_changed=true
preference_matches PerPaneBackgroundImage 1 || settings_changed=true
preference_matches DimOnlyText 1 || settings_changed=true
preference_matches ShowPaneTitles 1 || settings_changed=true
profile_matches || settings_changed=true

echo "=== VisualHUD iTerm2 Setup ==="
echo ""
if [ "$settings_changed" = true ]; then
    echo "--- Appearance Settings (defaults write) ---"
    defaults write com.googlecode.iterm2 HideTab -bool false
    defaults write com.googlecode.iterm2 TabViewType -int 1
    defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 5
    defaults write com.googlecode.iterm2 EnableAPIServer -bool true
    defaults write com.googlecode.iterm2 PerPaneBackgroundImage -bool true
    defaults write com.googlecode.iterm2 DimOnlyText -bool true
    defaults write com.googlecode.iterm2 ShowPaneTitles -bool true
    echo "  [x] Appearance preferences applied"
    mkdir -p "$DYNAMIC_DIR"
    profile_json > "$DYNAMIC_DIR/visualhud-profile.json"
    echo "  [x] Dynamic profile written to: $DYNAMIC_DIR/visualhud-profile.json"
else
    :
fi
echo ""
echo "=== Setup Complete ==="
if [ "$settings_changed" = true ]; then
    record_changed_restart_state
else
    report_unchanged_restart_state
fi
echo "To undo: $0 --reset"
