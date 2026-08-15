#!/bin/bash
# VisualHUD theme-driven status engine for Claude Code and Codex.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the terminal target for iTerm2 escape sequences.
# In a hook (non-interactive) context, /dev/tty is "device not configured" and
# writes silently drop — title/badge/colors disappear. Walk the parent process
# tree for a real controlling tty as a fallback.
resolve_tty_target() {
    if [ -n "${VISUALHUD_TTY:-}" ]; then
        printf '%s' "$VISUALHUD_TTY"
        return
    fi
    if [ -n "${VISUALHUD_TEST_CAPTURE_DIR:-}" ]; then
        mkdir -p "$VISUALHUD_TEST_CAPTURE_DIR" 2>/dev/null || true
        printf '%s/terminal.log' "$VISUALHUD_TEST_CAPTURE_DIR"
        return
    fi
    if [ -z "${VISUALHUD_NO_DEV_TTY:-}" ] && { printf '' > /dev/tty; } 2>/dev/null; then
        printf '/dev/tty'
        return
    fi
    local pid="$PPID" tty
    while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ]; do
        tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' \t\n' || true)
        case "$tty" in
            ''|'?'|'??') ;;
            /*) printf '%s' "$tty"; return ;;
            *)  printf '/dev/%s' "$tty"; return ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' \t\n' || true)
    done
    printf '/dev/null'
}

# Test-mode flag: print resolved TTY target and exit without consuming stdin.
if [ "${1:-}" = "--resolve-tty" ]; then
    resolve_tty_target
    exit 0
fi

INPUT=$(cat)
JSON_HELPER="${VISUALHUD_JSON_HELPER:-$SCRIPT_DIR/scripts/visualhud-json.js}"

json_helper() {
    node "$JSON_HELPER" "$@"
}

EVENT=$(printf '%s' "$INPUT" | json_helper event-name 2>/dev/null || true)
SOURCE_EVENT=$(printf '%s' "$INPUT" | json_helper field source_event 2>/dev/null || true)
START_SOURCE=$(printf '%s' "$INPUT" | json_helper field start_source 2>/dev/null || true)

if [ -z "$EVENT" ]; then
    case "${1:-}" in
        cooked) EVENT="Stop" ;;
        cooking|"") EVENT="PreToolUse" ;;
        *) EVENT="PreToolUse" ;;
    esac
fi

THEMES_DIR="${VISUALHUD_THEMES_DIR:-$SCRIPT_DIR/themes}"
ACTIVE_THEME_FILE="${VISUALHUD_THEME_FILE:-$SCRIPT_DIR/theme}"
THEME="${VISUALHUD_THEME:-}"
if [ -z "$THEME" ] && [ -f "$ACTIVE_THEME_FILE" ]; then
    THEME=$(tr -d '[:space:]' < "$ACTIVE_THEME_FILE")
fi
THEME="${THEME:-${VISUALHUD_DEFAULT_THEME:-pokemon}}"
THEME_FILE="$THEMES_DIR/$THEME/theme.json"
if [ ! -f "$THEME_FILE" ]; then
    THEME="${VISUALHUD_DEFAULT_THEME:-pokemon}"
    THEME_FILE="$THEMES_DIR/$THEME/theme.json"
fi
if [ ! -f "$THEME_FILE" ]; then
    THEME="pokemon"
    THEME_FILE="$THEMES_DIR/pokemon/theme.json"
fi

INPUT_SESSION_ID=$(printf '%s' "$INPUT" | json_helper field session_id 2>/dev/null || true)
SESSION_ID="${ITERM_SESSION_ID:-${WT_SESSION:-${WEZTERM_PANE:-${INPUT_SESSION_ID:-visualhud}}}}"
PROJECT_NAME=$(basename "$PWD")
SESSION_KEY=$(printf '%s' "$SESSION_ID" | tr ':/' '__')
VISUALHUD_STATE_ROOT="${VISUALHUD_STATE_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$VISUALHUD_STATE_ROOT" 2>/dev/null || true
COUNTER_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-counter_${SESSION_KEY}"
STAGE_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-stage_${SESSION_KEY}"
ATTENTION_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-attention_${SESSION_KEY}"
CONTEXT_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-context_${SESSION_KEY}"
REVIEW_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-review_${SESSION_KEY}"
MODEL_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-model_${SESSION_KEY}"
EFFORT_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-effort_${SESSION_KEY}"
LEGACY_BG_CLEAR_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-bg-clear_${SESSION_KEY}"
BG_CLEAR_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-bg-clear-v2_${SESSION_KEY}"
BG_TARGET_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-bg-target_${SESSION_KEY}"
BG_APPLY_LOCK="$VISUALHUD_STATE_ROOT/claude-cooking-bg-apply_${SESSION_KEY}.lock"
COMPACT_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-compacting_${SESSION_KEY}"
SUBAGENT_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-subagent_${SESSION_KEY}"
SUBAGENT_DIR="${SUBAGENT_FILE}.d"
SUBAGENT_LOCK="${SUBAGENT_DIR}.lock"
PERMISSION_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-permission_${SESSION_KEY}"
PERMISSION_DIR="${PERMISSION_FILE}.d"
PERMISSION_ACTIVE_DIR="${PERMISSION_FILE}.active.d"
PERMISSION_LOCK="${PERMISSION_DIR}.lock"
TOKENS_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-tokens_${SESSION_KEY}"
STOP_HISTORY_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-stop-history_${SESSION_KEY}"
LOOP_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-loop_${SESSION_KEY}"
PROJECT_PATH="${VISUALHUD_PROJECT_ROOT:-$PWD}"
PROJECT_CHECKSUM=$(printf '%s' "$PROJECT_PATH" | cksum)
PROJECT_KEY=${PROJECT_CHECKSUM%% *}
JOURNEY_KEY="${SESSION_KEY}_${PROJECT_KEY}"
JOURNEY_FILE="$VISUALHUD_STATE_ROOT/visualhud-journey_${JOURNEY_KEY}.json"
JOURNEY_HISTORY_FILE="$VISUALHUD_STATE_ROOT/visualhud-journey-history_${JOURNEY_KEY}.jsonl"
JOURNEY_LOCK="$VISUALHUD_STATE_ROOT/visualhud-journey_${JOURNEY_KEY}.lock"
JOURNEY_OPERATION_DIR="$VISUALHUD_STATE_ROOT/visualhud-journey-operations_${JOURNEY_KEY}.d"
AGGREGATE_FILE="$VISUALHUD_STATE_ROOT/visualhud-aggregate_${JOURNEY_KEY}"
REPAINT_TOKEN_FILE="$VISUALHUD_STATE_ROOT/visualhud-repaint_${JOURNEY_KEY}"
TURN_FAILURE_FILE="$VISUALHUD_STATE_ROOT/visualhud-turn-failure_${JOURNEY_KEY}"
SPRITES_DIR="${VISUALHUD_SPRITES_DIR:-$SCRIPT_DIR/sprites}"
SET_BG="${VISUALHUD_SET_BG:-$SCRIPT_DIR/set_bg.py}"
TTY_TARGET=$(resolve_tty_target)
RENDERER="${VISUALHUD_RENDERER:-}"
VISUALHUD_LOOP_WINDOW_SEC="${VISUALHUD_LOOP_WINDOW_SEC:-30}"
VISUALHUD_LOOP_THRESHOLD="${VISUALHUD_LOOP_THRESHOLD:-8}"
REQUESTED_JOURNEY_PROFILE="${VISUALHUD_JOURNEY_PROFILE:-}"
INPUT_JOURNEY_PROFILE=""
case "$INPUT" in
    *'"journey_profile"'*) INPUT_JOURNEY_PROFILE=$(printf '%s' "$INPUT" | json_helper field journey_profile 2>/dev/null || true) ;;
esac
if [ "$REQUESTED_JOURNEY_PROFILE" = "off" ]; then
    JOURNEY_PROFILE="off"
elif [ -n "$INPUT_JOURNEY_PROFILE" ]; then
    JOURNEY_PROFILE="$INPUT_JOURNEY_PROFILE"
elif [ -f "$JOURNEY_FILE" ]; then
    STORED_JOURNEY_PROFILE=$(json_helper field profile 2>/dev/null < "$JOURNEY_FILE" || true)
    case "$STORED_JOURNEY_PROFILE" in
        codex-default|sdlc|release) JOURNEY_PROFILE="$STORED_JOURNEY_PROFILE" ;;
        *) JOURNEY_PROFILE="$REQUESTED_JOURNEY_PROFILE" ;;
    esac
else
    JOURNEY_PROFILE="$REQUESTED_JOURNEY_PROFILE"
fi
JOURNEY_ENABLED=false
if [ -n "$JOURNEY_PROFILE" ] && [ "$JOURNEY_PROFILE" != "off" ] && [ "${VISUALHUD_ACTIVITY_MODE:-semantic}" != "legacy" ]; then
    JOURNEY_ENABLED=true
fi
JOURNEY_RENDER_JSON=""
AGGREGATE_STATUS=""
case "$INPUT" in
    *'"journey_aggregate"'*) AGGREGATE_STATUS=$(printf '%s' "$INPUT" | json_helper field journey_aggregate 2>/dev/null || true) ;;
esac
if [ -n "$AGGREGATE_STATUS" ]; then
    printf '%s' "$AGGREGATE_STATUS" > "$AGGREGATE_FILE" 2>/dev/null || true
elif [ -f "$AGGREGATE_FILE" ]; then
    AGGREGATE_STATUS=$(cat "$AGGREGATE_FILE" 2>/dev/null || true)
fi

if [ -z "$RENDERER" ]; then
    if [ -n "${WEZTERM_PANE:-}" ]; then
        RENDERER="wezterm"
    elif [ -n "${ITERM_SESSION_ID:-}" ]; then
        RENDERER="iterm2"
    elif [ -n "${WT_SESSION:-}" ]; then
        RENDERER="windows"
    else
        case "$(uname -s 2>/dev/null || printf unknown)" in
            MINGW*|MSYS*|CYGWIN*) RENDERER="windows" ;;
            *) RENDERER="iterm2" ;;
        esac
    fi
fi

BACKGROUND_API_ENABLED=false
if [ -n "${VISUALHUD_TEST_CAPTURE_DIR:-}" ] && [ -z "${VISUALHUD_SET_BG:-}" ]; then
    BACKGROUND_API_ENABLED=false
elif [ "$RENDERER" = "iterm2" ] && { [ -z "${VISUALHUD_TTY:-}" ] || [ -c "$TTY_TARGET" ]; }; then
    BACKGROUND_API_ENABLED=true
fi

to_hex() {
    printf '%02x' "$1"
}

to_tint() {
    printf '%02x' $(( $1 * 3 / 10 ))
}

progress_bar() {
    local stage="$1"
    json_helper progress-bar "$THEME_FILE" "$stage"
}

theme_state_json() {
    local state="$1" count="${2:-0}"
    json_helper state "$THEME_FILE" "$state" "$count"
}

theme_has_state() {
    [ "$(theme_state_json "$1")" != "null" ]
}

is_review_payload() {
    local json="$1"
    printf '%s' "$json" | json_helper review-payload >/dev/null 2>&1
}

sprite_path_for() {
    local sprite="$1"
    local theme_sprite="$THEMES_DIR/$THEME/sprites/${sprite}.png"
    local global_sprite="$SPRITES_DIR/${sprite}.png"

    if [ -f "$theme_sprite" ]; then
        printf '%s' "$theme_sprite"
    elif [ -f "$global_sprite" ]; then
        printf '%s' "$global_sprite"
    fi
}

release_background_lock() {
    local expected_owner="$1"
    [ "$(cat "$BG_APPLY_LOCK" 2>/dev/null || true)" = "$expected_owner" ] || return 0
    rm -f "$BG_APPLY_LOCK" 2>/dev/null || true
}

apply_background_path() {
    (
        local expected_path current_path lock_owner lock_pid lock_started lock_now
        local lock_value lock_attempt=0
        lock_pid="${BASHPID:-$$}"
        lock_started=$(date +%s)
        lock_value="${lock_pid}:${lock_started}"

        while ! (set -C; umask 077; printf '%s' "$lock_value" > "$BG_APPLY_LOCK") 2>/dev/null; do
            lock_attempt=$((lock_attempt + 1))
            if [ -d "$BG_APPLY_LOCK" ]; then
                rmdir "$BG_APPLY_LOCK" 2>/dev/null || exit 0
            else
                lock_owner=$(cat "$BG_APPLY_LOCK" 2>/dev/null || true)
                lock_pid=${lock_owner%%:*}
                lock_started=${lock_owner#*:}
                case "$lock_owner" in
                    *:*) ;;
                    *) lock_pid=""; lock_started="" ;;
                esac
                case "$lock_pid" in
                    ''|*[!0-9]*) rm -f "$BG_APPLY_LOCK" 2>/dev/null || exit 0 ;;
                    *)
                        case "$lock_started" in
                            ''|*[!0-9]*) rm -f "$BG_APPLY_LOCK" 2>/dev/null || exit 0 ;;
                            *)
                                lock_now=$(date +%s)
                                if kill -0 "$lock_pid" 2>/dev/null && [ $((lock_now - lock_started)) -lt 30 ]; then
                                    exit 0
                                fi
                                rm -f "$BG_APPLY_LOCK" 2>/dev/null || exit 0
                                ;;
                        esac
                        ;;
                esac
            fi
            [ "$lock_attempt" -lt 3 ] || exit 0
        done
        trap 'release_background_lock "$lock_value"' EXIT

        while :; do
            expected_path=$(cat "$BG_TARGET_FILE" 2>/dev/null || true)
            python3 "$SET_BG" "$expected_path" "$SESSION_ID" 2>/dev/null
            current_path=$(cat "$BG_TARGET_FILE" 2>/dev/null || true)
            [ "$current_path" != "$expected_path" ] || break
        done

        trap - EXIT
        release_background_lock "$lock_value"
        current_path=$(cat "$BG_TARGET_FILE" 2>/dev/null || true)
        if [ "$current_path" != "$expected_path" ]; then
            apply_background_path "$current_path"
        fi
    ) >/dev/null 2>&1 &
}

badge_text_for() {
    local badge_emoji="$1"
    printf '%s' "$badge_emoji"
}

terminal_columns() {
    local columns="${VISUALHUD_TITLE_WIDTH:-${COLUMNS:-}}" size

    case "$columns" in
        ''|*[!0-9]*) ;;
        *) printf '%s' "$columns"; return ;;
    esac

    if [ -c "$TTY_TARGET" ]; then
        size=$(stty -f "$TTY_TARGET" size 2>/dev/null || stty -F "$TTY_TARGET" size 2>/dev/null || true)
        columns=${size##* }
        case "$columns" in
            ''|*[!0-9]*) ;;
            *) printf '%s' "$columns"; return ;;
        esac
    fi

    printf '0'
}

journey_title() {
    local progress="$1" badge="$2" stage_name="$3" stage_num="$4" journey_total="$5"
    local context_title="${6:-}" overlay_label="${7:-}"
    local checkpoint title_width core compact with_progress with_project full suffix=""

    checkpoint="${stage_name%% · *}"
    core="${stage_num}/${journey_total} ${checkpoint}"
    if [ -n "$badge" ]; then
        core="${core} ${badge}"
    fi

    title_width=$(terminal_columns)
    with_progress="${progress} ${core}"
    with_project="${with_progress} | ${PROJECT_NAME}"
    full="$with_project"
    if [ -n "${AGGREGATE_STATUS:-}" ]; then
        full="${full} | ${AGGREGATE_STATUS}"
    fi
    if [ -n "$overlay_label" ]; then
        suffix=" | ${overlay_label}"
    fi
    if [ -n "$context_title" ]; then
        suffix="${suffix} | ${context_title}"
    fi
    compact="$core"
    if [ -n "$overlay_label" ]; then
        compact="${compact} ${overlay_label}"
    fi

    json_helper fit-title "$title_width" \
        "${full}${suffix}" \
        "${with_project}${suffix}" \
        "${with_progress}${suffix}" \
        "${core}${suffix}" \
        "$compact" \
        "$core"
}

journey_overlay_label() {
    case "$1" in
        permission) printf 'HITL' ;;
        blocked) printf 'BLOCKED' ;;
        compacting) printf 'COMPACT' ;;
        subagent) printf 'AGENT' ;;
        error) printf 'Error' ;;
        review) printf 'REVIEW' ;;
        working) printf 'WORK' ;;
        *) printf '%s' "$1" | tr '[:lower:]' '[:upper:]' ;;
    esac
}

context_percent_from_json() {
    local json="$1" percent

    percent=$(printf '%s' "$json" | json_helper context-percent-json 2>/dev/null || true)
    if [ -n "$percent" ]; then
        printf '%s' "$percent"
    fi
}

codex_session_file_for() {
    local session_id="$1" sessions_root

    if [ -n "${VISUALHUD_CODEX_SESSION_FILE:-}" ] && [ -f "$VISUALHUD_CODEX_SESSION_FILE" ]; then
        printf '%s' "$VISUALHUD_CODEX_SESSION_FILE"
        return 0
    fi

    [ -n "$session_id" ] || return 0
    sessions_root="${CODEX_HOME:-$HOME/.codex}/sessions"
    [ -d "$sessions_root" ] || return 0

    find "$sessions_root" -maxdepth 4 -type f -name "*${session_id}.jsonl" -print -quit 2>/dev/null
}

context_percent_from_session_file() {
    local session_file="$1"
    [ -f "$session_file" ] || return 0

    json_helper context-percent-session "$session_file" 2>/dev/null || true
}

context_percent_from_input() {
    local env_percent="${VISUALHUD_CONTEXT_USED_PERCENT:-}" percent session_id session_file

    if [ -n "$env_percent" ]; then
        printf '{"context_used_percent":"%s"}' "$env_percent" | json_helper context-percent-json 2>/dev/null || true
        return 0
    fi

    percent=$(context_percent_from_json "$INPUT")
    if [ -n "$percent" ]; then
        printf '%s' "$percent"
        return 0
    fi

    session_id=$(printf '%s' "$INPUT" | json_helper field session_id 2>/dev/null || true)
    session_file=$(codex_session_file_for "$session_id")
    if [ -n "$session_file" ]; then
        context_percent_from_session_file "$session_file"
    fi
}

context_alert_json() {
    local percent="$1"
    [ -n "$percent" ] || return 0

    json_helper context-alert "$THEME_FILE" "$percent" 2>/dev/null || true
}

# Track Stop fires inside the window; set LOOP_FILE when threshold is exceeded.
# Catches /goal Stop-hook deadlocks where Claude can't satisfy an unmet condition
# and silently spirals — without this, the loop is invisible until user notices.
detect_stop_loop() {
    local now cutoff kept count
    now=$(date +%s 2>/dev/null || printf 0)
    [ -n "$now" ] && [ "$now" -gt 0 ] 2>/dev/null || return 1
    printf '%d\n' "$now" >> "$STOP_HISTORY_FILE" 2>/dev/null || true
    cutoff=$(( now - VISUALHUD_LOOP_WINDOW_SEC ))
    if [ -f "$STOP_HISTORY_FILE" ]; then
        kept=$(awk -v cutoff="$cutoff" '$1+0 >= cutoff+0 { print }' "$STOP_HISTORY_FILE" 2>/dev/null || true)
        printf '%s\n' "$kept" > "$STOP_HISTORY_FILE" 2>/dev/null || true
        count=$(printf '%s\n' "$kept" | grep -c '^[0-9]' 2>/dev/null || printf 0)
        if [ "$count" -ge "$VISUALHUD_LOOP_THRESHOLD" ] 2>/dev/null; then
            touch "$LOOP_FILE" 2>/dev/null || true
            return 0
        fi
    fi
    return 1
}

emit_loop_status() {
    local count="$1" title badge r=255 g=40 b=40 rh gh bh tr tg tb
    title="LOOP DETECTED (${count} stops/${VISUALHUD_LOOP_WINDOW_SEC}s) — run /goal clear"
    badge="LOOP"
    rh=$(to_hex "$r"); gh=$(to_hex "$g"); bh=$(to_hex "$b")
    tr=$(to_tint "$r"); tg=$(to_tint "$g"); tb=$(to_tint "$b")
    emit_iterm_status "$TTY_TARGET" "$badge" "$tr" "$tg" "$tb" "$rh" "$gh" "$bh" "$r" "$g" "$b" "$title" ""
}

emit_iterm_status() {
    local tty_target="$1" badge_text="$2" tr="$3" tg="$4" tb="$5" rh="$6" gh="$7" bh="$8" r="$9"
    shift 9
    local g="$1" b="$2" title="$3" context_title="$4"

    {
        printf '\033]1337;SetBadgeFormat=%s\a' "$(printf '%s' "$badge_text" | base64)"
        printf '\033]1337;SetColors=bg=%s%s%s\a' "$tr" "$tg" "$tb"
        printf '\033]1337;SetColors=black=%s%s%s\a' "$tr" "$tg" "$tb"
        printf '\033]1337;SetColors=selbg=%s%s%s\a' "$tr" "$tg" "$tb"
        printf '\033]1337;SetColors=tab=%s%s%s\a' "$rh" "$gh" "$bh"
        printf '\033]1337;SetColors=br_black=%s%s%s\a' "$tr" "$tg" "$tb"
        printf '\033]6;1;bg;red;brightness;%d\a' "$r"
        printf '\033]6;1;bg;green;brightness;%d\a' "$g"
        printf '\033]6;1;bg;blue;brightness;%d\a' "$b"
        printf '\033]1337;SetColors=curbg=%s%s%s\a' "$rh" "$gh" "$bh"
        printf '\033]0;%s\a' "$title"
        printf '\033]1337;SetUserVar=%s=%s\007' "hudProgress" "$(printf '%s' "$title" | base64)"
        printf '\033]1337;SetUserVar=%s=%s\007' "hudContext" "$(printf '%s' "$context_title" | base64)"
        printf '\033]1337;SetUserVar=%s=%s\007' "hudEffort" "$(printf '%s' "${EFFORT_LEVEL:-}" | base64)"
        printf '\033]1337;SetUserVar=%s=%s\007' "hudCost" "$(printf '%s' "${TOKEN_TOTAL:-}" | base64)"
        printf '\033]1337;SetUserVar=%s=%s\007' "hudAggregate" "$(printf '%s' "${AGGREGATE_STATUS:-}" | base64)"
    } >> "$tty_target" 2>/dev/null || true
}

windows_progress_state() {
    local state_kind="$1" context_alert="$2"
    case "$state_kind" in
        working)
            printf '3'
            ;;
        error)
            printf '2'
            ;;
        blocked)
            printf '4'
            ;;
        review)
            printf '3'
            ;;
        progress)
            if [ -n "$context_alert" ]; then
                printf '4'
            else
                printf '1'
            fi
            ;;
        journey)
            if [ -n "$context_alert" ]; then
                printf '4'
            else
                printf '1'
            fi
            ;;
        *)
            printf '0'
            ;;
    esac
}

windows_progress_percent() {
    local stage_num="$1" state_kind="$2" journey_total="${3:-}" limit
    case "$state_kind" in
        progress)
            limit=$(json_helper progress-bar-length "$THEME_FILE" 2>/dev/null || printf '0')
            if [ -n "$stage_num" ] && [ "$limit" -gt 0 ]; then
                printf '%d' $((stage_num * 100 / limit))
            else
                printf '0'
            fi
            ;;
        journey)
            if [ -n "$stage_num" ] && [ -n "$journey_total" ] && [ "$journey_total" -gt 0 ]; then
                printf '%d' $((stage_num * 100 / journey_total))
            else
                printf '0'
            fi
            ;;
        *)
            printf '0'
            ;;
    esac
}

emit_windows_status() {
    local tty_target="$1" title="$2" stage_num="$3" state_kind="$4" context_alert="$5" journey_total="${6:-}"
    local progress_state progress_percent

    progress_state=$(windows_progress_state "$state_kind" "$context_alert")
    progress_percent=$(windows_progress_percent "$stage_num" "$state_kind" "$journey_total")
    {
        printf '\033]0;%s\a' "$title"
        printf '\033]9;4;%s;%s\a' "$progress_state" "$progress_percent"
    } >> "$tty_target" 2>/dev/null || true
}

emit_wezterm_status() {
    local tty_target="$1" badge_text="$2" title="$3" context_title="$4" stage_num="$5" state_kind="$6"
    local sprite_path="$7" color_hex="$8" tint_hex="$9" stage_name="${10}" journey_total="${11:-}" progress_percent state_b64 render_stage

    progress_percent=$(windows_progress_percent "$stage_num" "$state_kind" "$journey_total")
    render_stage="$stage_num"
    if [ "$state_kind" != "progress" ] && [ "$state_kind" != "journey" ]; then
        render_stage=""
    fi
    state_b64=$(json_helper wezterm-state \
        "$title" \
        "$context_title" \
        "$sprite_path" \
        "$color_hex" \
        "$tint_hex" \
        "$render_stage" \
        "$state_kind" \
        "$progress_percent" \
        "$badge_text" \
        "$stage_name" \
        "$PROJECT_NAME")

    {
        printf '\033]0;%s\a' "$title"
        printf '\033]1337;SetUserVar=%s=%s\007' "visualhudState" "$state_b64"
    } >> "$tty_target" 2>/dev/null || true
}

emit_terminal_status() {
    local tty_target="$1" badge_text="$2" tr="$3" tg="$4" tb="$5" rh="$6" gh="$7" bh="$8" r="$9"
    shift 9
    local g="$1" b="$2" title="$3" context_title="$4" stage_num="${5:-}" state_kind="${6:-progress}" context_alert="${7:-}" sprite_path="${8:-}" stage_name="${9:-}" journey_total="${10:-}"

    case "$RENDERER" in
        wezterm)
            emit_wezterm_status "$tty_target" "$badge_text" "$title" "$context_title" "$stage_num" "$state_kind" "$sprite_path" "#${rh}${gh}${bh}" "#${tr}${tg}${tb}" "$stage_name" "$journey_total"
            ;;
        windows|win32|powershell|windows-terminal)
            emit_windows_status "$tty_target" "$title" "$stage_num" "$state_kind" "$context_alert" "$journey_total"
            ;;
        *)
            emit_iterm_status "$tty_target" "$badge_text" "$tr" "$tg" "$tb" "$rh" "$gh" "$bh" "$r" "$g" "$b" "$title" "$context_title"
            ;;
    esac
}

set_status_from_json() {
    local state_json="$1" fallback_stage_num="${2:-}" state_kind="${3:-progress}"
    local r g b sprite badge_emoji stage_name stage_num rh gh bh tr tg tb badge_text title sprite_path
    local context_alert context_level context_percent context_badge context_name context_title reapply_delay reapply_delays
    local repaint_token repaint_token_tmp
    local state_fields state_progress_bar state_journey_total background_should_apply last_background_path
    local journey_overlay=false overlay_label journey_state_json journey_fields
    local journey_name journey_num journey_progress journey_total

    state_fields=$(printf '%s' "$state_json" | json_helper state-fields)
    IFS=$'\037' read -r r g b sprite badge_emoji stage_name stage_num state_progress_bar state_journey_total <<< "$state_fields"
    stage_num="${stage_num:-$fallback_stage_num}"

    rh=$(to_hex "$r")
    gh=$(to_hex "$g")
    bh=$(to_hex "$b")
    tr=$(to_tint "$r")
    tg=$(to_tint "$g")
    tb=$(to_tint "$b")

    if [ "$state_kind" = "journey" ] && [ -n "$stage_num" ]; then
        badge_text=$(badge_text_for "$badge_emoji" "$stage_name" "$stage_num")
        title=$(journey_title "$state_progress_bar" "$badge_emoji" "$stage_name" "$stage_num" "$state_journey_total")
    elif [ "$state_kind" = "progress" ] && [ -n "$stage_num" ]; then
        badge_text=$(badge_text_for "$badge_emoji" "$stage_name" "$stage_num")
        if [ -n "$stage_name" ]; then
            title="$(progress_bar "$stage_num") ${badge_emoji} ${stage_name} — ${PROJECT_NAME}"
        else
            title="$(progress_bar "$stage_num") ${badge_emoji} ${PROJECT_NAME}"
        fi
    elif [ -n "$stage_name" ]; then
        badge_text=$(badge_text_for "$badge_emoji" "$stage_name" "")
        title="${badge_emoji} ${stage_name} — ${PROJECT_NAME}"
    else
        badge_text=$(badge_text_for "$badge_emoji" "" "")
        title="${badge_emoji} ${PROJECT_NAME}"
    fi

    if [ "$JOURNEY_ENABLED" = "true" ] && [ "$state_kind" != "journey" ] && [ "$state_kind" != "progress" ]; then
        journey_state_json="$JOURNEY_RENDER_JSON"
        if [ -z "$journey_state_json" ] && [ -f "$JOURNEY_FILE" ]; then
            journey_state_json=$(json_helper journey-render-file "$THEME_FILE" "$JOURNEY_PROFILE" "$JOURNEY_FILE")
        fi
        if [ -n "$journey_state_json" ] && [ "$journey_state_json" != "null" ]; then
            journey_fields=$(printf '%s' "$journey_state_json" | json_helper state-fields)
            IFS=$'\037' read -r _ _ _ _ _ journey_name journey_num journey_progress journey_total <<< "$journey_fields"
            if [ -n "$journey_num" ] && [ -n "$journey_total" ]; then
                overlay_label=$(journey_overlay_label "$state_kind")
                title=$(journey_title "$journey_progress" "" "$journey_name" "$journey_num" "$journey_total" "" "$overlay_label")
                journey_overlay=true
            fi
        fi
    fi

    context_alert="${CONTEXT_ALERT_JSON:-}"
    if [ -n "$context_alert" ]; then
        local alert_fields
        alert_fields=$(printf '%s' "$context_alert" | json_helper alert-fields)
        IFS=$'\037' read -r context_level context_percent context_badge context_name <<< "$alert_fields"

        badge_text="${badge_text} ${context_badge}${context_percent}"
        context_title="${context_name} CTX ${context_percent}%"
        if [ "$journey_overlay" = "true" ]; then
            title=$(journey_title "$journey_progress" "" "$journey_name" "$journey_num" "$journey_total" "$context_title" "$overlay_label")
        elif [ "$state_kind" = "journey" ] && [ -n "$stage_num" ]; then
            title=$(journey_title "$state_progress_bar" "$badge_emoji" "$stage_name" "$stage_num" "$state_journey_total" "$context_title")
        else
            title="${title} | ${context_title}"
        fi
        printf '%s:%s' "$context_level" "$context_percent" > "$CONTEXT_FILE" 2>/dev/null || true
    else
        context_title=""
        rm -f "$CONTEXT_FILE" 2>/dev/null
    fi

    sprite_path=$(sprite_path_for "$sprite")
    printf '%s' "$sprite" > "$STAGE_FILE" 2>/dev/null || true
    background_should_apply=false
    last_background_path=$(cat "$BG_TARGET_FILE" 2>/dev/null || true)
    if [ ! -f "$BG_TARGET_FILE" ] || [ "$last_background_path" != "$sprite_path" ] || [ "${BACKGROUND_RESTORE_REQUESTED:-false}" = "true" ]; then
        background_should_apply=true
    else
        case "$EVENT" in
            PreCompact|PostCompact|Stop) background_should_apply=true ;;
        esac
    fi
    repaint_token="$$:${RANDOM:-0}"
    repaint_token_tmp="${REPAINT_TOKEN_FILE}.$$"
    printf '%s' "$repaint_token" > "$repaint_token_tmp" 2>/dev/null || true
    mv "$repaint_token_tmp" "$REPAINT_TOKEN_FILE" 2>/dev/null || true
    emit_terminal_status "$TTY_TARGET" "$badge_text" "$tr" "$tg" "$tb" "$rh" "$gh" "$bh" "$r" "$g" "$b" "$title" "$context_title" "$stage_num" "$state_kind" "$context_alert" "$sprite_path" "$stage_name" "$state_journey_total"
    if [ "$background_should_apply" = "true" ] && [ "$BACKGROUND_API_ENABLED" = "true" ] && [ "${VISUALHUD_BG:-off}" = "on" ] && [ -f "$SET_BG" ]; then
        printf '%s' "$sprite_path" > "$BG_TARGET_FILE" 2>/dev/null || true
        apply_background_path "$sprite_path"
    fi
    reapply_delay="${VISUALHUD_REAPPLY_DELAY:-0}"
    reapply_delays="${VISUALHUD_REAPPLY_DELAYS:-$reapply_delay}"
    if [ -n "$reapply_delays" ] && [ "$reapply_delays" != "0" ]; then
        (
            local_reapply_index=0
            for reapply_delay in $reapply_delays; do
                [ -n "$reapply_delay" ] && [ "$reapply_delay" != "0" ] || continue
                sleep "$reapply_delay"
                [ "$(cat "$REPAINT_TOKEN_FILE" 2>/dev/null || true)" = "$repaint_token" ] || exit 0
                emit_terminal_status "$TTY_TARGET" "$badge_text" "$tr" "$tg" "$tb" "$rh" "$gh" "$bh" "$r" "$g" "$b" "$title" "$context_title" "$stage_num" "$state_kind" "$context_alert" "$sprite_path" "$stage_name" "$state_journey_total"
                if [ "$local_reapply_index" -eq 0 ] && [ "$BACKGROUND_API_ENABLED" = "true" ] && [ "${VISUALHUD_BG:-off}" = "on" ] && [ -f "$SET_BG" ]; then
                    apply_background_path "$sprite_path"
                fi
                local_reapply_index=$((local_reapply_index + 1))
            done
        ) >/dev/null 2>&1 &
    fi
}

set_named_state() {
    local state="$1"
    set_status_from_json "$(theme_state_json "$state")" "" "$state"
}

acquire_journey_lock() {
    local attempt=0
    while ! mkdir "$JOURNEY_LOCK" 2>/dev/null; do
        attempt=$((attempt + 1))
        [ "$attempt" -lt 500 ] || return 1
        sleep 0.01
    done
}

release_journey_lock() {
    rmdir "$JOURNEY_LOCK" 2>/dev/null || true
}

journey_apply_signal() {
    [ "$JOURNEY_ENABLED" = "true" ] || return 1
    acquire_journey_lock || return 1
    trap release_journey_lock EXIT
    JOURNEY_RENDER_JSON=$(printf '%s' "$INPUT" | json_helper journey-apply \
        "$JOURNEY_PROFILE" "$JOURNEY_FILE" "$JOURNEY_HISTORY_FILE" \
        "$JOURNEY_OPERATION_DIR" "$THEME_FILE")
    release_journey_lock
    trap - EXIT
}

journey_complete_read_only() {
    [ "$JOURNEY_ENABLED" = "true" ] || return 1
    [ "$JOURNEY_PROFILE" = "codex-default" ] || return 0
    acquire_journey_lock || return 1
    trap release_journey_lock EXIT
    JOURNEY_RENDER_JSON=$(json_helper journey-complete-read-only \
        "$JOURNEY_PROFILE" "$JOURNEY_FILE" "$JOURNEY_HISTORY_FILE" "$THEME_FILE")
    release_journey_lock
    trap - EXIT
}

journey_reset_if_done() {
    local current
    [ "$JOURNEY_ENABLED" = "true" ] || return 1
    [ -f "$JOURNEY_FILE" ] || return 0
    acquire_journey_lock || return 1
    trap release_journey_lock EXIT
    current=$(json_helper field current 2>/dev/null < "$JOURNEY_FILE" || true)
    if [ "$current" = "done" ]; then
        rm -rf "$JOURNEY_OPERATION_DIR" 2>/dev/null
        rm -f "$JOURNEY_FILE" "$AGGREGATE_FILE" 2>/dev/null
        AGGREGATE_STATUS=""
        JOURNEY_RENDER_JSON=""
        JOURNEY_PROFILE="${REQUESTED_JOURNEY_PROFILE:-$JOURNEY_PROFILE}"
    fi
    release_journey_lock
    trap - EXIT
}

render_journey() {
    local state_json
    [ "$JOURNEY_ENABLED" = "true" ] || return 1
    if [ -z "$JOURNEY_RENDER_JSON" ]; then
        if [ ! -f "$JOURNEY_FILE" ]; then
            journey_apply_signal || return 1
        else
            JOURNEY_RENDER_JSON=$(json_helper journey-render-file "$THEME_FILE" "$JOURNEY_PROFILE" "$JOURNEY_FILE")
        fi
    fi
    state_json="$JOURNEY_RENDER_JSON"
    set_status_from_json "$state_json" "" journey
}

emit_hitl_notification() {
    if [ "$RENDERER" = "iterm2" ]; then
        printf '\033]9;VisualHUD HITL: approval required\a' >> "$TTY_TARGET" 2>/dev/null || true
    fi
}

CONTEXT_PERCENT=$(context_percent_from_input)
CONTEXT_ALERT_JSON=$(context_alert_json "$CONTEXT_PERCENT")

# Self-heal stale iTerm2 BG image once per pane when VISUALHUD_BG is off.
# Upgrading from v0.x (BG defaulted on) leaves a cached sprite in iTerm2's
# per-pane state; with compact-by-default we never call set_bg.py again, so
# the stale image sticks forever. One explicit clear per pane fixes it.
# Toggling VISUALHUD_BG=on removes the marker so off→on→off re-triggers.
BACKGROUND_RESTORE_REQUESTED=false
if [ "$BACKGROUND_API_ENABLED" != "true" ]; then
    :
elif [ "${VISUALHUD_BG:-off}" = "on" ]; then
    if [ -f "$BG_CLEAR_FILE" ]; then
        BACKGROUND_RESTORE_REQUESTED=true
    fi
    rm -f "$LEGACY_BG_CLEAR_FILE" "$BG_CLEAR_FILE" 2>/dev/null
elif [ ! -f "$BG_CLEAR_FILE" ] && [ -f "$SET_BG" ]; then
    printf '' > "$BG_TARGET_FILE" 2>/dev/null || true
    apply_background_path ""
    touch "$BG_CLEAR_FILE" 2>/dev/null
    rm -f "$LEGACY_BG_CLEAR_FILE" 2>/dev/null
fi
PERMISSION_MODE=$(printf '%s' "$INPUT" | json_helper field permission_mode 2>/dev/null || true)
EFFORT_LEVEL=$(printf '%s' "$INPUT" | json_helper field effort.level 2>/dev/null || true)
if [ -n "$EFFORT_LEVEL" ]; then
    printf '%s' "$EFFORT_LEVEL" > "$EFFORT_FILE" 2>/dev/null
elif [ -f "$EFFORT_FILE" ]; then
    EFFORT_LEVEL=$(cat "$EFFORT_FILE" 2>/dev/null)
fi

# Sum tokens from transcript_path (assistant lines only).
# Adds input + cache_creation + cache_read + output across all assistant messages.
# Persists running total in TOKENS_FILE; falls back to last-known on missing/bad path.
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | json_helper field transcript_path 2>/dev/null || true)
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    TOKEN_TOTAL=$(json_helper transcript-token-total "$TRANSCRIPT_PATH" 2>/dev/null || printf 0)
    if [ -n "$TOKEN_TOTAL" ]; then
        printf '%s' "$TOKEN_TOTAL" > "$TOKENS_FILE" 2>/dev/null
    fi
elif [ -f "$TOKENS_FILE" ]; then
    TOKEN_TOTAL=$(cat "$TOKENS_FILE" 2>/dev/null)
fi

# True iff input is permission_mode=plan AND active theme defines a .plan state.
in_plan_mode() {
    [ "$PERMISSION_MODE" = "plan" ] \
        && theme_has_state "plan"
}

permission_input_key() {
    local input_key
    input_key=$(printf '%s' "$INPUT" | json_helper field permission_key 2>/dev/null || true)
    printf '%s' "${input_key:-uncorrelated}"
}

permission_marker_path() {
    local key="$1" checksum
    checksum=$(printf '%s' "$key" | cksum | awk '{print $1}')
    printf '%s/%s' "$PERMISSION_DIR" "$checksum"
}

permission_active_marker_path() {
    local key="$1" checksum
    checksum=$(printf '%s' "$key" | cksum | awk '{print $1}')
    printf '%s/%s' "$PERMISSION_ACTIVE_DIR" "$checksum"
}

acquire_permission_lock() {
    local attempt=0
    while ! mkdir "$PERMISSION_LOCK" 2>/dev/null; do
        attempt=$((attempt + 1))
        [ "$attempt" -lt 500 ] || return 1
        sleep 0.01
    done
}

release_permission_lock() {
    rmdir "$PERMISSION_LOCK" 2>/dev/null || true
}

permission_add() {
    local key="$1" state="$2" marker stored_key count stored_state
    acquire_permission_lock || return 1
    trap release_permission_lock EXIT
    mkdir -p "$PERMISSION_DIR" 2>/dev/null
    marker=$(permission_marker_path "$key")
    stored_key=$(cut -f1 "$marker" 2>/dev/null || true)
    count=0
    stored_state=""
    if [ "$stored_key" = "$key" ]; then
        count=$(cut -f2 "$marker" 2>/dev/null || printf 0)
        stored_state=$(cut -f3 "$marker" 2>/dev/null || true)
        if ! [ "$count" -ge 1 ] 2>/dev/null; then
            stored_state="$count"
            count=1
        fi
    fi
    if [ "$stored_state" = "blocked" ]; then
        state="blocked"
    fi
    printf '%s\t%d\t%s\n' "$key" "$((count + 1))" "$state" > "$marker" 2>/dev/null
    rm -f "$PERMISSION_FILE" 2>/dev/null
    release_permission_lock
    trap - EXIT
}

permission_remove_input() {
    local key marker stored_key count state
    key=$(permission_input_key)
    acquire_permission_lock || return 1
    trap release_permission_lock EXIT
    marker=$(permission_marker_path "$key")
    stored_key=$(cut -f1 "$marker" 2>/dev/null || true)
    if [ "$stored_key" != "$key" ]; then
        release_permission_lock
        trap - EXIT
        return 1
    fi
    count=$(cut -f2 "$marker" 2>/dev/null || printf 1)
    state=$(cut -f3 "$marker" 2>/dev/null || true)
    if ! [ "$count" -ge 1 ] 2>/dev/null; then
        state="$count"
        count=1
    fi
    if [ "$count" -gt 1 ]; then
        printf '%s\t%d\t%s\n' "$key" "$((count - 1))" "$state" > "$marker" 2>/dev/null
    else
        rm -f "$marker" 2>/dev/null
    fi
    rmdir "$PERMISSION_DIR" 2>/dev/null || true
    release_permission_lock
    trap - EXIT
}

permission_active_add_input() {
    local key marker stored_key count
    key=$(permission_input_key)
    acquire_permission_lock || return 1
    trap release_permission_lock EXIT
    mkdir -p "$PERMISSION_ACTIVE_DIR" 2>/dev/null
    marker=$(permission_active_marker_path "$key")
    stored_key=$(cut -f1 "$marker" 2>/dev/null || true)
    count=0
    if [ "$stored_key" = "$key" ]; then
        count=$(cut -f2 "$marker" 2>/dev/null || printf 0)
    fi
    printf '%s\t%d\n' "$key" "$((count + 1))" > "$marker" 2>/dev/null
    release_permission_lock
    trap - EXIT
}

permission_active_remove_input() {
    local key marker stored_key count
    key=$(permission_input_key)
    acquire_permission_lock || return 1
    trap release_permission_lock EXIT
    marker=$(permission_active_marker_path "$key")
    stored_key=$(cut -f1 "$marker" 2>/dev/null || true)
    if [ "$stored_key" != "$key" ]; then
        release_permission_lock
        trap - EXIT
        return 1
    fi
    count=$(cut -f2 "$marker" 2>/dev/null || printf 1)
    if [ "$count" -gt 1 ]; then
        printf '%s\t%d\n' "$key" "$((count - 1))" > "$marker" 2>/dev/null
    else
        rm -f "$marker" 2>/dev/null
        rmdir "$PERMISSION_ACTIVE_DIR" 2>/dev/null || true
    fi
    release_permission_lock
    trap - EXIT
}

permission_pending() {
    [ -d "$PERMISSION_DIR" ] && [ -n "$(find "$PERMISSION_DIR" -type f -print -quit 2>/dev/null)" ]
}

permission_pending_state() {
    if grep -l $'\tblocked$' "$PERMISSION_DIR"/* >/dev/null 2>&1; then
        printf 'blocked'
    else
        printf 'permission'
    fi
}

render_pending_permission() {
    local state
    acquire_permission_lock || return 1
    trap release_permission_lock EXIT
    if ! permission_pending; then
        rm -f "$ATTENTION_FILE" 2>/dev/null
        release_permission_lock
        trap - EXIT
        return 1
    fi
    state=$(permission_pending_state)
    printf '%s' "$state" > "$ATTENTION_FILE" 2>/dev/null
    if [ "$state" = "blocked" ]; then
        set_named_state "blocked"
    else
        set_named_state "permission"
    fi
    release_permission_lock
    trap - EXIT
}

clear_permissions() {
    rm -f "$PERMISSION_FILE" 2>/dev/null
    rm -rf "$PERMISSION_DIR" "$PERMISSION_ACTIVE_DIR" "$PERMISSION_LOCK" 2>/dev/null
}

acquire_subagent_lock() {
    local attempt=0
    while ! mkdir "$SUBAGENT_LOCK" 2>/dev/null; do
        attempt=$((attempt + 1))
        [ "$attempt" -lt 500 ] || return 1
        sleep 0.01
    done
}

release_subagent_lock() {
    rmdir "$SUBAGENT_LOCK" 2>/dev/null || true
}

subagent_marker_path() {
    local agent_id="$1" checksum
    checksum=$(printf '%s' "$agent_id" | cksum | awk '{print $1}')
    printf '%s/%s' "$SUBAGENT_DIR" "$checksum"
}

subagent_active() {
    [ -d "$SUBAGENT_DIR" ] && [ -n "$(find "$SUBAGENT_DIR" -type f -print -quit 2>/dev/null)" ]
}

if [ "$JOURNEY_ENABLED" = "true" ] && ! { [ "$EVENT" = "Stop" ] && [ "$SOURCE_EVENT" = "SessionStart" ]; }; then
    journey_apply_signal || true
fi

case "$EVENT" in
    UserPromptSubmit)
        # Reset working counter + attention, but preserve REVIEW_FILE.
        # A user message during an in-flight code review (background shell still
        # running) must not flip the state to 'done' on the next Stop.
        # A user message also breaks any /goal Stop loop in progress — clear loop state.
        rm -f "$COUNTER_FILE" "$ATTENTION_FILE" "$TURN_FAILURE_FILE" "$STOP_HISTORY_FILE" "$LOOP_FILE" 2>/dev/null
        clear_permissions
        if [ "$JOURNEY_ENABLED" = "true" ]; then
            journey_reset_if_done || true
        fi
        if in_plan_mode; then
            if [ "$JOURNEY_ENABLED" = "true" ]; then
                render_journey
            else
                set_named_state "plan"
            fi
        elif [ "$JOURNEY_ENABLED" = "true" ]; then
            render_journey
        fi
        exit 0
        ;;
    CwdChanged)
        NEW_CWD=$(printf '%s' "$INPUT" | json_helper field cwd 2>/dev/null || true)
        if [ -n "$NEW_CWD" ] && [ -d "$NEW_CWD" ]; then
            PROJECT_NAME=$(basename "$NEW_CWD")
            rm -f "$COUNTER_FILE" "$ATTENTION_FILE" "$REVIEW_FILE" "$STAGE_FILE" 2>/dev/null
            clear_permissions
            set_named_state "idle"
        fi
        exit 0
        ;;
    SessionStart)
        SESSION_MODEL=$(printf '%s' "$INPUT" | json_helper field model 2>/dev/null || true)
        SESSION_SOURCE=$(printf '%s' "$INPUT" | json_helper field source 2>/dev/null || true)
        if [ -n "$SESSION_MODEL" ]; then
            printf '%s' "$SESSION_MODEL" > "$MODEL_FILE" 2>/dev/null
        fi
        # /clear or post-compact: fresh slate (counter, attention, review, stage)
        case "$SESSION_SOURCE" in
            clear|compact)
                rm -f "$COUNTER_FILE" "$ATTENTION_FILE" "$REVIEW_FILE" "$STAGE_FILE" 2>/dev/null
                clear_permissions
                ;;
        esac
        if [ "$JOURNEY_ENABLED" = "true" ]; then
            render_journey
        fi
        exit 0
        ;;
    PreCompact)
        # Theme can opt in via .compacting state. Glitch/MISSINGNO moment in Pokemon.
        if theme_has_state "compacting"; then
            touch "$COMPACT_FILE" 2>/dev/null
            set_named_state "compacting"
        fi
        exit 0
        ;;
    PostCompact)
        rm -f "$COMPACT_FILE" 2>/dev/null
        if [ "$JOURNEY_ENABLED" = "true" ]; then
            render_journey
        fi
        exit 0
        ;;
    SubagentStart)
        if theme_has_state "subagent"; then
            SUBAGENT_TYPE=$(printf '%s' "$INPUT" | json_helper field agent_type 2>/dev/null || true)
            SUBAGENT_ID=$(printf '%s' "$INPUT" | json_helper field agent_id 2>/dev/null || true)
            SUBAGENT_ID=$(printf '%s' "${SUBAGENT_ID:-type-$SUBAGENT_TYPE}" | tr '\t\r\n' '___')
            acquire_subagent_lock || exit 0
            trap release_subagent_lock EXIT
            mkdir -p "$SUBAGENT_DIR" 2>/dev/null
            printf '%s\t%s\n' "$SUBAGENT_ID" "$SUBAGENT_TYPE" > "$(subagent_marker_path "$SUBAGENT_ID")" 2>/dev/null
            set_named_state "subagent"
            release_subagent_lock
            trap - EXIT
        fi
        exit 0
        ;;
    SubagentStop)
        SUBAGENT_ID=$(printf '%s' "$INPUT" | json_helper field agent_id 2>/dev/null || true)
        acquire_subagent_lock || exit 0
        trap release_subagent_lock EXIT
        if [ -n "$SUBAGENT_ID" ] && [ -d "$SUBAGENT_DIR" ]; then
            SUBAGENT_ID=$(printf '%s' "$SUBAGENT_ID" | tr '\t\r\n' '___')
            rm -f "$(subagent_marker_path "$SUBAGENT_ID")" 2>/dev/null
        else
            rm -rf "$SUBAGENT_DIR" 2>/dev/null
        fi
        if subagent_active; then
            set_named_state "subagent"
            release_subagent_lock
            trap - EXIT
            exit 0
        fi
        rmdir "$SUBAGENT_DIR" 2>/dev/null || true
        if [ -f "$ATTENTION_FILE" ]; then
            ATTENTION_STATE=$(cat "$ATTENTION_FILE" 2>/dev/null || true)
            case "$ATTENTION_STATE" in
                error) set_named_state "error" ;;
                permission) set_named_state "permission" ;;
                *) set_named_state "blocked" ;;
            esac
        elif [ "$JOURNEY_ENABLED" = "true" ]; then
            render_journey
        elif in_plan_mode; then
            set_named_state "plan"
        elif [ -f "$REVIEW_FILE" ]; then
            set_named_state "review"
        elif theme_has_state "working"; then
            set_named_state "working"
        fi
        release_subagent_lock
        trap - EXIT
        exit 0
        ;;
    PostToolUse)
        if permission_active_remove_input; then
            :
        elif ! permission_remove_input; then
            if [ "$JOURNEY_ENABLED" = "true" ]; then
                render_journey
            fi
            exit 0
        fi
        if permission_pending; then
            render_pending_permission
            exit 0
        fi
        rm -f "$ATTENTION_FILE" 2>/dev/null
        if subagent_active; then
            set_named_state "subagent"
        elif [ "$JOURNEY_ENABLED" = "true" ]; then
            render_journey
        elif in_plan_mode; then
            set_named_state "plan"
        elif [ -f "$REVIEW_FILE" ]; then
            set_named_state "review"
        elif theme_has_state "working"; then
            set_named_state "working"
        fi
        exit 0
        ;;
    PostToolUseFailure)
        # Roll back optimistic activity and flash the error. Journey mode also
        # latches the failure through Stop so later tools cannot erase it.
        ROLLBACK_ACTIVITY=$(printf '%s' "$INPUT" | json_helper field rollback_activity 2>/dev/null || true)
        REVIEW_FAILURE=$(printf '%s' "$INPUT" | json_helper field review_failure 2>/dev/null || true)
        if [ "$ROLLBACK_ACTIVITY" != "false" ] && [ -f "$COUNTER_FILE" ]; then
            current=$(cat "$COUNTER_FILE" 2>/dev/null)
            if [ -n "$current" ] && [ "$current" -gt 0 ] 2>/dev/null; then
                printf '%d' "$((current - 1))" > "$COUNTER_FILE" 2>/dev/null
            fi
        fi
        if [ "$REVIEW_FAILURE" = "true" ] || { [ -z "$REVIEW_FAILURE" ] && is_review_payload "$INPUT"; }; then
            rm -f "$REVIEW_FILE" 2>/dev/null
        fi
        if [ "$JOURNEY_ENABLED" = "true" ]; then
            printf 'error' > "$ATTENTION_FILE" 2>/dev/null
            printf 'error' > "$TURN_FAILURE_FILE" 2>/dev/null
        fi
        if permission_active_remove_input; then
            if permission_pending; then
                render_pending_permission
                exit 0
            fi
        elif permission_pending; then
            if permission_remove_input && permission_pending; then
                render_pending_permission
                exit 0
            elif permission_pending; then
                render_pending_permission
                exit 0
            fi
            rm -f "$ATTENTION_FILE" 2>/dev/null
        fi
        set_named_state "error"
        exit 0
        ;;
    Notification)
        NOTIF_TYPE=$(printf '%s' "$INPUT" | json_helper field notification_type 2>/dev/null || true)
        if [ "$NOTIF_TYPE" = "permission_prompt" ]; then
            NOTIF_KEY=$(printf '%s' "$INPUT" | json_helper field permission_key 2>/dev/null || true)
            permission_add "${NOTIF_KEY:-uncorrelated}" "blocked"
            printf 'blocked' > "$ATTENTION_FILE" 2>/dev/null
            set_named_state "blocked"
            emit_hitl_notification
        elif [ "$NOTIF_TYPE" = "permission_check" ] && theme_has_state "permission"; then
            NOTIF_KEY=$(printf '%s' "$INPUT" | json_helper field permission_key 2>/dev/null || true)
            permission_add "${NOTIF_KEY:-uncorrelated}" "permission"
            printf 'permission' > "$ATTENTION_FILE" 2>/dev/null
            set_named_state "permission"
        elif [ "$NOTIF_TYPE" = "idle_prompt" ]; then
            rm -f "$COUNTER_FILE" "$ATTENTION_FILE" 2>/dev/null
            clear_permissions
            if [ -f "$REVIEW_FILE" ]; then
                set_named_state "review"
            else
                set_named_state "idle"
            fi
        fi
        exit 0
        ;;
    StopFailure)
        printf 'error' > "$ATTENTION_FILE" 2>/dev/null
        rm -f "$REVIEW_FILE" 2>/dev/null
        set_named_state "error"
        exit 0
        ;;
    JourneyUpdate)
        JOURNEY_OUTCOME=$(printf '%s' "$INPUT" | json_helper field journey_outcome 2>/dev/null || true)
        if [ "$JOURNEY_OUTCOME" = "transient" ]; then
            set_named_state "error"
        elif [ "$JOURNEY_ENABLED" = "true" ]; then
            render_journey
        fi
        exit 0
        ;;
    TaskCompleted)
        if [ -f "$REVIEW_FILE" ] || is_review_payload "$INPUT"; then
            permission_active_remove_input || true
            rm -f "$COUNTER_FILE" "$REVIEW_FILE" 2>/dev/null
            if permission_pending; then
                render_pending_permission
            elif [ "$JOURNEY_ENABLED" = "true" ]; then
                rm -f "$ATTENTION_FILE" 2>/dev/null
                render_journey
            else
                rm -f "$ATTENTION_FILE" 2>/dev/null
                set_named_state "done"
            fi
        fi
        exit 0
        ;;
    Stop)
        STOP_HAD_ERROR=false
        if [ -f "$TURN_FAILURE_FILE" ]; then
            STOP_HAD_ERROR=true
        fi
        rm -f "$COUNTER_FILE" "$ATTENTION_FILE" "$TURN_FAILURE_FILE" 2>/dev/null
        clear_permissions
        if [ "$SOURCE_EVENT" = "SessionStart" ]; then
            case "$START_SOURCE" in
                resume|compact)
                    if [ "$JOURNEY_ENABLED" = "true" ] && [ -f "$JOURNEY_FILE" ]; then
                        render_journey
                    else
                        set_named_state "idle"
                    fi
                    ;;
                *)
                    rm -rf "$JOURNEY_OPERATION_DIR" 2>/dev/null
                    rm -f "$JOURNEY_FILE" "$AGGREGATE_FILE" "$TURN_FAILURE_FILE" "$REVIEW_FILE" 2>/dev/null
                    AGGREGATE_STATUS=""
                    set_named_state "idle"
                    ;;
            esac
            exit 0
        fi
        if detect_stop_loop; then
            loop_count=$(wc -l < "$STOP_HISTORY_FILE" 2>/dev/null | tr -d ' ')
            emit_loop_status "${loop_count:-?}"
            exit 0
        fi
        if [ -f "$REVIEW_FILE" ] || is_review_payload "$INPUT"; then
            printf 'review' > "$REVIEW_FILE" 2>/dev/null
            if [ "$JOURNEY_ENABLED" = "true" ]; then
                render_journey
            else
                set_named_state "review"
            fi
        elif [ "$JOURNEY_ENABLED" = "true" ]; then
            rm -f "$REVIEW_FILE" 2>/dev/null
            if [ "$STOP_HAD_ERROR" != "true" ]; then
                journey_complete_read_only || true
            fi
            render_journey
        else
            rm -f "$REVIEW_FILE" 2>/dev/null
            set_named_state "done"
        fi
        exit 0
        ;;
    PreToolUse|*)
        PENDING_PERMISSION_RENDER=false
        if permission_pending; then
            if permission_remove_input; then
                permission_active_add_input || true
            fi
            if permission_pending; then
                PENDING_PERMISSION_RENDER=true
            fi
        fi
        rm -f "$ATTENTION_FILE" "$PERMISSION_FILE" 2>/dev/null
        if is_review_payload "$INPUT"; then
            printf 'review' > "$REVIEW_FILE" 2>/dev/null
            if [ "$PENDING_PERMISSION_RENDER" = "true" ]; then
                render_pending_permission
            elif [ "$JOURNEY_ENABLED" = "true" ]; then
                render_journey
            else
                set_named_state "review"
            fi
            exit 0
        fi
        if in_plan_mode; then
            if [ "$PENDING_PERMISSION_RENDER" = "true" ]; then
                render_pending_permission
            elif [ "$JOURNEY_ENABLED" = "true" ]; then
                render_journey
            else
                set_named_state "plan"
            fi
            exit 0
        fi
        ;;
esac

if [ "$JOURNEY_ENABLED" = "true" ]; then
    render_journey
    exit 0
fi

count=1
[ -f "$COUNTER_FILE" ] && count=$(( $(cat "$COUNTER_FILE") + 1 ))
printf '%d' "$count" > "$COUNTER_FILE" 2>/dev/null

if [ "${PENDING_PERMISSION_RENDER:-false}" = "true" ]; then
    render_pending_permission
elif [ "${VISUALHUD_ACTIVITY_MODE:-semantic}" = "legacy" ] || ! theme_has_state "working"; then
    stage_index=$(json_helper stage-index "$THEME_FILE" "$count")
    set_status_from_json "$(theme_state_json "progress" "$count")" "$((stage_index + 1))"
else
    set_named_state "working"
fi
