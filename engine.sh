#!/bin/bash
# VisualHUD theme-driven status engine for Claude Code and Codex.

set -euo pipefail

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_HELPER="${VISUALHUD_JSON_HELPER:-$SCRIPT_DIR/scripts/visualhud-json.js}"

json_helper() {
    node "$JSON_HELPER" "$@"
}

EVENT=$(printf '%s' "$INPUT" | json_helper event-name 2>/dev/null || true)

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
SESSION_ID="${ITERM_SESSION_ID:-${WT_SESSION:-${INPUT_SESSION_ID:-visualhud}}}"
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
BG_CLEAR_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-bg-clear_${SESSION_KEY}"
COMPACT_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-compacting_${SESSION_KEY}"
SUBAGENT_FILE="$VISUALHUD_STATE_ROOT/claude-cooking-subagent_${SESSION_KEY}"
SPRITES_DIR="${VISUALHUD_SPRITES_DIR:-$SCRIPT_DIR/sprites}"
SET_BG="${VISUALHUD_SET_BG:-$SCRIPT_DIR/set_bg.py}"
TTY_TARGET="${VISUALHUD_TTY:-/dev/tty}"
RENDERER="${VISUALHUD_RENDERER:-}"

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

badge_text_for() {
    local badge_emoji="$1"
    printf '%s' "$badge_emoji"
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
    } >> "$tty_target" 2>/dev/null || true
}

windows_progress_state() {
    local state_kind="$1" context_alert="$2"
    case "$state_kind" in
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
        *)
            printf '0'
            ;;
    esac
}

windows_progress_percent() {
    local stage_num="$1" state_kind="$2" limit
    case "$state_kind" in
        progress|review)
            limit=$(json_helper progress-bar-length "$THEME_FILE" 2>/dev/null || printf '0')
            if [ -n "$stage_num" ] && [ "$limit" -gt 0 ]; then
                printf '%d' $((stage_num * 100 / limit))
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
    local tty_target="$1" title="$2" stage_num="$3" state_kind="$4" context_alert="$5"
    local progress_state progress_percent

    progress_state=$(windows_progress_state "$state_kind" "$context_alert")
    progress_percent=$(windows_progress_percent "$stage_num" "$state_kind")
    {
        printf '\033]0;%s\a' "$title"
        printf '\033]9;4;%s;%s\a' "$progress_state" "$progress_percent"
    } >> "$tty_target" 2>/dev/null || true
}

emit_wezterm_status() {
    local tty_target="$1" badge_text="$2" title="$3" context_title="$4" stage_num="$5" state_kind="$6"
    local sprite_path="$7" color_hex="$8" tint_hex="$9" stage_name="${10}" progress_percent state_b64

    progress_percent=$(windows_progress_percent "$stage_num" "$state_kind")
    state_b64=$(json_helper wezterm-state \
        "$title" \
        "$context_title" \
        "$sprite_path" \
        "$color_hex" \
        "$tint_hex" \
        "$stage_num" \
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
    local g="$1" b="$2" title="$3" context_title="$4" stage_num="${5:-}" state_kind="${6:-progress}" context_alert="${7:-}" sprite_path="${8:-}" stage_name="${9:-}"

    case "$RENDERER" in
        wezterm)
            emit_wezterm_status "$tty_target" "$badge_text" "$title" "$context_title" "$stage_num" "$state_kind" "$sprite_path" "#${rh}${gh}${bh}" "#${tr}${tg}${tb}" "$stage_name"
            ;;
        windows|win32|powershell|windows-terminal)
            emit_windows_status "$tty_target" "$title" "$stage_num" "$state_kind" "$context_alert"
            ;;
        *)
            emit_iterm_status "$tty_target" "$badge_text" "$tr" "$tg" "$tb" "$rh" "$gh" "$bh" "$r" "$g" "$b" "$title" "$context_title"
            ;;
    esac
}

set_status_from_json() {
    local state_json="$1" fallback_stage_num="${2:-}" state_kind="${3:-progress}"
    local r g b sprite badge_emoji stage_name stage_num rh gh bh tr tg tb badge_text title sprite_path
    local context_alert context_level context_percent context_badge context_name context_title reapply_delay
    local state_fields

    state_fields=$(printf '%s' "$state_json" | json_helper state-fields)
    IFS=$'\037' read -r r g b sprite badge_emoji stage_name stage_num <<< "$state_fields"
    stage_num="${stage_num:-$fallback_stage_num}"

    rh=$(to_hex "$r")
    gh=$(to_hex "$g")
    bh=$(to_hex "$b")
    tr=$(to_tint "$r")
    tg=$(to_tint "$g")
    tb=$(to_tint "$b")

    if [ -n "$stage_num" ]; then
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

    context_alert="${CONTEXT_ALERT_JSON:-}"
    if [ -n "$context_alert" ]; then
        local alert_fields
        alert_fields=$(printf '%s' "$context_alert" | json_helper alert-fields)
        IFS=$'\037' read -r context_level context_percent context_badge context_name <<< "$alert_fields"

        badge_text="${badge_text} ${context_badge}${context_percent}"
        context_title="${context_name} CTX ${context_percent}%"
        title="${title} | ${context_title}"
        printf '%s:%s' "$context_level" "$context_percent" > "$CONTEXT_FILE" 2>/dev/null || true
    else
        context_title=""
        rm -f "$CONTEXT_FILE" 2>/dev/null
    fi

    sprite_path=$(sprite_path_for "$sprite")
    emit_terminal_status "$TTY_TARGET" "$badge_text" "$tr" "$tg" "$tb" "$rh" "$gh" "$bh" "$r" "$g" "$b" "$title" "$context_title" "$stage_num" "$state_kind" "$context_alert" "$sprite_path" "$stage_name"
    reapply_delay="${VISUALHUD_REAPPLY_DELAY:-0}"
    if [ -n "$reapply_delay" ] && [ "$reapply_delay" != "0" ]; then
        (
            sleep "$reapply_delay"
            emit_terminal_status "$TTY_TARGET" "$badge_text" "$tr" "$tg" "$tb" "$rh" "$gh" "$bh" "$r" "$g" "$b" "$title" "$context_title" "$stage_num" "$state_kind" "$context_alert" "$sprite_path" "$stage_name"
        ) >/dev/null 2>&1 &
    fi

    local last_stage=""
    [ -f "$STAGE_FILE" ] && last_stage=$(cat "$STAGE_FILE")
    if [ "$sprite" != "$last_stage" ] && [ -n "$sprite" ]; then
        printf '%s' "$sprite" > "$STAGE_FILE" 2>/dev/null
        # Background sprite is opt-in. Default is compact mode (no full-pane sprite).
        # Enable with VISUALHUD_BG=on for the full-pane sprite background.
        if [ "$RENDERER" = "iterm2" ] && [ "${VISUALHUD_BG:-off}" = "on" ] && [ -f "$SET_BG" ]; then
            sprite_path=$(sprite_path_for "$sprite")
            python3 "$SET_BG" "$sprite_path" "$SESSION_ID" 2>/dev/null &
        fi
    fi
}

set_named_state() {
    local state="$1"
    set_status_from_json "$(theme_state_json "$state")" "" "$state"
}

CONTEXT_PERCENT=$(context_percent_from_input)
CONTEXT_ALERT_JSON=$(context_alert_json "$CONTEXT_PERCENT")

# Self-heal stale iTerm2 BG image once per pane when VISUALHUD_BG is off.
# Upgrading from v0.x (BG defaulted on) leaves a cached sprite in iTerm2's
# per-pane state; with compact-by-default we never call set_bg.py again, so
# the stale image sticks forever. One explicit clear per pane fixes it.
# Toggling VISUALHUD_BG=on removes the marker so off→on→off re-triggers.
if [ "$RENDERER" != "iterm2" ]; then
    :
elif [ "${VISUALHUD_BG:-off}" = "on" ]; then
    rm -f "$BG_CLEAR_FILE" 2>/dev/null
elif [ ! -f "$BG_CLEAR_FILE" ] && [ -f "$SET_BG" ]; then
    python3 "$SET_BG" "" "$SESSION_ID" 2>/dev/null &
    touch "$BG_CLEAR_FILE" 2>/dev/null
fi
PERMISSION_MODE=$(printf '%s' "$INPUT" | json_helper field permission_mode 2>/dev/null || true)
EFFORT_LEVEL=$(printf '%s' "$INPUT" | json_helper field effort.level 2>/dev/null || true)
if [ -n "$EFFORT_LEVEL" ]; then
    printf '%s' "$EFFORT_LEVEL" > "$EFFORT_FILE" 2>/dev/null
elif [ -f "$EFFORT_FILE" ]; then
    EFFORT_LEVEL=$(cat "$EFFORT_FILE" 2>/dev/null)
fi

# True iff input is permission_mode=plan AND active theme defines a .plan state.
in_plan_mode() {
    [ "$PERMISSION_MODE" = "plan" ] \
        && theme_has_state "plan"
}

case "$EVENT" in
    UserPromptSubmit)
        # Reset working counter + attention, but preserve REVIEW_FILE.
        # A user message during an in-flight code review (background shell still
        # running) must not flip the state to 'done' on the next Stop.
        rm -f "$COUNTER_FILE" "$ATTENTION_FILE" 2>/dev/null
        if in_plan_mode; then
            set_named_state "plan"
        fi
        exit 0
        ;;
    CwdChanged)
        NEW_CWD=$(printf '%s' "$INPUT" | json_helper field cwd 2>/dev/null || true)
        if [ -n "$NEW_CWD" ] && [ -d "$NEW_CWD" ]; then
            PROJECT_NAME=$(basename "$NEW_CWD")
            rm -f "$COUNTER_FILE" "$ATTENTION_FILE" "$REVIEW_FILE" "$STAGE_FILE" 2>/dev/null
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
                ;;
        esac
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
        exit 0
        ;;
    SubagentStart)
        if theme_has_state "subagent"; then
            SUBAGENT_TYPE=$(printf '%s' "$INPUT" | json_helper field agent_type 2>/dev/null || true)
            printf '%s' "$SUBAGENT_TYPE" > "$SUBAGENT_FILE" 2>/dev/null
            set_named_state "subagent"
        fi
        exit 0
        ;;
    SubagentStop)
        rm -f "$SUBAGENT_FILE" 2>/dev/null
        exit 0
        ;;
    PostToolUseFailure)
        # Success-weighted progress: roll back the optimistic increment from PreToolUse
        # and flash error state (without persisting attention — next PreToolUse clears).
        if [ -f "$COUNTER_FILE" ]; then
            current=$(cat "$COUNTER_FILE" 2>/dev/null)
            if [ -n "$current" ] && [ "$current" -gt 0 ] 2>/dev/null; then
                printf '%d' "$((current - 1))" > "$COUNTER_FILE" 2>/dev/null
            fi
        fi
        set_named_state "error"
        exit 0
        ;;
    Notification)
        NOTIF_TYPE=$(printf '%s' "$INPUT" | json_helper field notification_type 2>/dev/null || true)
        if [ "$NOTIF_TYPE" = "permission_prompt" ]; then
            printf 'blocked' > "$ATTENTION_FILE" 2>/dev/null
            set_named_state "blocked"
        elif [ "$NOTIF_TYPE" = "idle_prompt" ]; then
            rm -f "$COUNTER_FILE" "$ATTENTION_FILE" 2>/dev/null
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
    TaskCompleted)
        if [ -f "$REVIEW_FILE" ] || is_review_payload "$INPUT"; then
            rm -f "$COUNTER_FILE" "$ATTENTION_FILE" "$REVIEW_FILE" 2>/dev/null
            set_named_state "done"
        fi
        exit 0
        ;;
    Stop)
        rm -f "$COUNTER_FILE" "$ATTENTION_FILE" 2>/dev/null
        if [ -f "$REVIEW_FILE" ] || is_review_payload "$INPUT"; then
            printf 'review' > "$REVIEW_FILE" 2>/dev/null
            set_named_state "review"
        else
            rm -f "$REVIEW_FILE" 2>/dev/null
            set_named_state "done"
        fi
        exit 0
        ;;
    PreToolUse|*)
        rm -f "$ATTENTION_FILE" 2>/dev/null
        if is_review_payload "$INPUT"; then
            printf 'review' > "$REVIEW_FILE" 2>/dev/null
            set_named_state "review"
            exit 0
        fi
        if in_plan_mode; then
            set_named_state "plan"
            exit 0
        fi
        ;;
esac

count=1
[ -f "$COUNTER_FILE" ] && count=$(( $(cat "$COUNTER_FILE") + 1 ))
printf '%d' "$count" > "$COUNTER_FILE" 2>/dev/null

stage_index=$(json_helper stage-index "$THEME_FILE" "$count")
set_status_from_json "$(theme_state_json "progress" "$count")" "$((stage_index + 1))"
