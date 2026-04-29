#!/bin/bash
# VisualHUD theme-driven status engine for Claude Code and Codex.

set -euo pipefail

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)

if [ -z "$EVENT" ]; then
    case "${1:-}" in
        cooked) EVENT="Stop" ;;
        cooking|"") EVENT="PreToolUse" ;;
        *) EVENT="PreToolUse" ;;
    esac
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

SESSION_ID="${ITERM_SESSION_ID:-}"
PROJECT_NAME=$(basename "$PWD")
SESSION_KEY=$(printf '%s' "$SESSION_ID" | tr ':/' '__')
COUNTER_FILE="/private/tmp/claude-cooking-counter_${SESSION_KEY}"
STAGE_FILE="/private/tmp/claude-cooking-stage_${SESSION_KEY}"
ATTENTION_FILE="/private/tmp/claude-cooking-attention_${SESSION_KEY}"
CONTEXT_FILE="/private/tmp/claude-cooking-context_${SESSION_KEY}"
SPRITES_DIR="${VISUALHUD_SPRITES_DIR:-$SCRIPT_DIR/sprites}"
SET_BG="${VISUALHUD_SET_BG:-$SCRIPT_DIR/set_bg.py}"
TTY_TARGET="${VISUALHUD_TTY:-/dev/tty}"

to_hex() {
    printf '%02x' "$1"
}

to_tint() {
    printf '%02x' $(( $1 * 3 / 10 ))
}

progress_bar() {
    local stage="$1" i bar token limit
    limit=$(jq -r '(.progress_bar // []) | length' "$THEME_FILE")
    if [ "$limit" -le 0 ]; then
        limit="$stage"
    fi
    bar=""
    for ((i=0; i<stage && i<limit; i++)); do
        token=$(jq -r --argjson idx "$i" '.progress_bar[$idx] // "■"' "$THEME_FILE")
        bar="${bar}${token}"
    done
    printf '%s' "$bar"
}

theme_state_json() {
    local state="$1" count="${2:-0}"
    case "$state" in
        progress)
            jq -c --argjson count "$count" '
              def clamp($value; $min; $max):
                if $value < $min then $min
                elif $value > $max then $max
                else $value
                end;

              .stages as $stages
              | (
                  [$stages | to_entries[] | select(($count <= .value.max) or (.value.max == null))][0]
                  // ($stages | to_entries | last)
                ) as $entry
              | ($entry.key) as $idx
              | ($entry.value) as $stage
              | (if $idx == 0 then 1 else (($stages[$idx - 1].max // 0) + 1) end) as $start
              | ($stage.shades // []) as $shades
              | if ($shades | length) > 1 then
                  (
                    if (($stage.max // 999999) >= 999999) then
                      (
                        if $idx == 0 then
                          (($shades | length) * 20)
                        else
                          ($stages[$idx - 1].max // ($start - 1)) as $previous_max
                          | (if $idx <= 1 then 1 else (($stages[$idx - 2].max // 0) + 1) end) as $previous_start
                          | (($previous_max - $previous_start + 1) * ($shades | length))
                        end
                      ) as $span
                      | clamp(((($count - $start) * ($shades | length) / $span) | floor); 0; (($shades | length) - 1))
                    else
                      ($stage.max - $start + 1) as $span
                      | clamp(((($count - $start) * ($shades | length) / $span) | floor); 0; (($shades | length) - 1))
                    end
                  ) as $shade_index
                  | (
                      $stage
                      + {color: $shades[$shade_index], active_shade: ($shade_index + 1)}
                      + (
                          if (($stage.shade_sprites // []) | length) > $shade_index then
                            {base_sprite: $stage.sprite, sprite: $stage.shade_sprites[$shade_index]}
                          else
                            {}
                          end
                        )
                    )
                else
                  $stage
                end
            ' "$THEME_FILE"
            ;;
        *)
            jq -c --arg state "$state" '.[$state]' "$THEME_FILE"
            ;;
    esac
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

    percent=$(printf '%s' "$json" | jq -r '
      def num:
        if type == "number" then .
        elif type == "string" then (sub("%$"; "") | tonumber?)
        else empty
        end;
      [
        (.context_used_percent? | num),
        (.context_percent? | num),
        (.context.used_percent? | num),
        (.context.percent_used? | num),
        (.context_usage.used_percent? | num),
        (.context_usage.percent_used? | num),
        (.token_usage.context_used_percent? | num),
        (.info.context_used_percent? | num),
        (.payload.info.context_used_percent? | num)
      ] | map(select(. != null)) | .[0] // empty | floor
    ' 2>/dev/null || true)
    if [ -n "$percent" ]; then
        printf '%s' "$percent"
        return 0
    fi

    printf '%s' "$json" | jq -r '
      def pct($tokens; $window):
        if (($tokens | type) == "number" and ($window | type) == "number" and $window > 0)
        then (($tokens * 100 / $window) | floor)
        else empty
        end;
      [
        pct(.info.last_token_usage.total_tokens?; .info.model_context_window?),
        pct(.payload.info.last_token_usage.total_tokens?; .payload.info.model_context_window?),
        pct(.token_count.info.last_token_usage.total_tokens?; .token_count.info.model_context_window?),
        pct(.token_usage.last_token_usage.total_tokens?; .token_usage.model_context_window?),
        pct(.last_token_usage.total_tokens?; .model_context_window?)
      ] | map(select(. != null)) | .[0] // empty
    ' 2>/dev/null || true
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

    tail -n 200 "$session_file" 2>/dev/null | jq -r '
      select(.type == "event_msg" and .payload.type == "token_count" and .payload.info != null)
      | [.payload.info.last_token_usage.total_tokens, .payload.info.model_context_window]
      | select(.[0] != null and .[1] != null and .[1] > 0)
      | ((.[0] * 100 / .[1]) | floor)
    ' 2>/dev/null | tail -n 1
}

context_percent_from_input() {
    local env_percent="${VISUALHUD_CONTEXT_USED_PERCENT:-}" percent session_id session_file

    if [ -n "$env_percent" ]; then
        jq -n -r --arg value "$env_percent" '$value | sub("%$"; "") | tonumber? | floor' 2>/dev/null || true
        return 0
    fi

    percent=$(context_percent_from_json "$INPUT")
    if [ -n "$percent" ]; then
        printf '%s' "$percent"
        return 0
    fi

    session_id=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
    session_file=$(codex_session_file_for "$session_id")
    if [ -n "$session_file" ]; then
        context_percent_from_session_file "$session_file"
    fi
}

context_alert_json() {
    local percent="$1"
    [ -n "$percent" ] || return 0

    jq -c --argjson percent "$percent" '
      def cfg($level): ((.context_alerts // {})[$level] // {});
      def alert($level; $fallback_min; $fallback_badge; $fallback_name; $fallback_color):
        (cfg($level) + {
          level: $level,
          percent: $percent,
          min_percent: (cfg($level).min_percent // $fallback_min),
          badge: (cfg($level).badge // $fallback_badge),
          name: (cfg($level).name // $fallback_name),
          color: (cfg($level).color // $fallback_color)
        });
      if $percent >= ((cfg("critical").min_percent // 85)) then
        alert("critical"; 85; "CTX!"; "Context Critical"; [255, 45, 45])
      elif $percent >= ((cfg("warning").min_percent // 70)) then
        alert("warning"; 70; "CTX"; "Context High"; [255, 190, 40])
      else
        empty
      end
    ' "$THEME_FILE" 2>/dev/null || true
}

emit_terminal_status() {
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
    } >> "$tty_target" 2>/dev/null || true
}

set_status_from_json() {
    local state_json="$1" fallback_stage_num="${2:-}"
    local r g b sprite badge_emoji stage_name stage_num rh gh bh tr tg tb badge_text title sprite_path
    local context_alert context_level context_percent context_badge context_name context_title reapply_delay

    r=$(printf '%s' "$state_json" | jq -r '.color[0]')
    g=$(printf '%s' "$state_json" | jq -r '.color[1]')
    b=$(printf '%s' "$state_json" | jq -r '.color[2]')
    sprite=$(printf '%s' "$state_json" | jq -r '.sprite // ""')
    badge_emoji=$(printf '%s' "$state_json" | jq -r '.badge // ""')
    stage_name=$(printf '%s' "$state_json" | jq -r '.name // ""')
    stage_num=$(printf '%s' "$state_json" | jq -r '.stage // empty')
    stage_num="${stage_num:-$fallback_stage_num}"

    rh=$(to_hex "$r")
    gh=$(to_hex "$g")
    bh=$(to_hex "$b")
    tr=$(to_tint "$r")
    tg=$(to_tint "$g")
    tb=$(to_tint "$b")

    if [ -n "$stage_num" ]; then
        badge_text=$(badge_text_for "$badge_emoji" "$stage_name" "$stage_num")
        title="$(progress_bar "$stage_num") ${badge_emoji} ${stage_name} — ${PROJECT_NAME}"
    elif [ -n "$stage_name" ]; then
        badge_text=$(badge_text_for "$badge_emoji" "$stage_name" "")
        title="${badge_emoji} ${stage_name} — ${PROJECT_NAME}"
    else
        badge_text=$(badge_text_for "$badge_emoji" "" "")
        title="${badge_emoji} — ${PROJECT_NAME}"
    fi

    context_alert="${CONTEXT_ALERT_JSON:-}"
    if [ -n "$context_alert" ]; then
        context_level=$(printf '%s' "$context_alert" | jq -r '.level')
        context_percent=$(printf '%s' "$context_alert" | jq -r '.percent')
        context_badge=$(printf '%s' "$context_alert" | jq -r '.badge')
        context_name=$(printf '%s' "$context_alert" | jq -r '.name')

        badge_text="${badge_text} ${context_badge}${context_percent}"
        context_title="${context_name} CTX ${context_percent}%"
        title="${title} | ${context_title}"
        printf '%s:%s' "$context_level" "$context_percent" > "$CONTEXT_FILE" 2>/dev/null || true
    else
        context_title=""
        rm -f "$CONTEXT_FILE" 2>/dev/null
    fi

    emit_terminal_status "$TTY_TARGET" "$badge_text" "$tr" "$tg" "$tb" "$rh" "$gh" "$bh" "$r" "$g" "$b" "$title" "$context_title"
    reapply_delay="${VISUALHUD_REAPPLY_DELAY:-0}"
    if [ -n "$reapply_delay" ] && [ "$reapply_delay" != "0" ]; then
        (
            sleep "$reapply_delay"
            emit_terminal_status "$TTY_TARGET" "$badge_text" "$tr" "$tg" "$tb" "$rh" "$gh" "$bh" "$r" "$g" "$b" "$title" "$context_title"
        ) >/dev/null 2>&1 &
    fi

    local last_stage=""
    [ -f "$STAGE_FILE" ] && last_stage=$(cat "$STAGE_FILE")
    if [ "$sprite" != "$last_stage" ] && [ -n "$sprite" ]; then
        printf '%s' "$sprite" > "$STAGE_FILE" 2>/dev/null
        sprite_path=$(sprite_path_for "$sprite")
        if [ -f "$SET_BG" ]; then
            python3 "$SET_BG" "$sprite_path" "$SESSION_ID" 2>/dev/null &
        fi
    fi
}

set_named_state() {
    local state="$1"
    set_status_from_json "$(theme_state_json "$state")"
}

CONTEXT_PERCENT=$(context_percent_from_input)
CONTEXT_ALERT_JSON=$(context_alert_json "$CONTEXT_PERCENT")

case "$EVENT" in
    UserPromptSubmit)
        rm -f "$COUNTER_FILE" "$ATTENTION_FILE" 2>/dev/null
        exit 0
        ;;
    Notification)
        NOTIF_TYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // empty')
        if [ "$NOTIF_TYPE" = "permission_prompt" ]; then
            printf 'blocked' > "$ATTENTION_FILE" 2>/dev/null
            set_named_state "blocked"
        elif [ "$NOTIF_TYPE" = "idle_prompt" ]; then
            rm -f "$COUNTER_FILE" "$ATTENTION_FILE" 2>/dev/null
            set_named_state "idle"
        fi
        exit 0
        ;;
    StopFailure)
        printf 'error' > "$ATTENTION_FILE" 2>/dev/null
        set_named_state "error"
        exit 0
        ;;
    TaskCompleted)
        exit 0
        ;;
    Stop)
        rm -f "$COUNTER_FILE" "$ATTENTION_FILE" 2>/dev/null
        set_named_state "done"
        exit 0
        ;;
    PreToolUse|*)
        rm -f "$ATTENTION_FILE" 2>/dev/null
        ;;
esac

count=1
[ -f "$COUNTER_FILE" ] && count=$(( $(cat "$COUNTER_FILE") + 1 ))
printf '%d' "$count" > "$COUNTER_FILE" 2>/dev/null

stage_index=$(jq -r --argjson count "$count" '
  .stages
  | to_entries
  | map(select($count <= .value.max))
  | .[0].key // ((.stages | length) - 1)
' "$THEME_FILE")
set_status_from_json "$(theme_state_json "progress" "$count")" "$((stage_index + 1))"
