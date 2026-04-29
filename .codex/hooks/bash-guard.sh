#!/bin/bash
# PreToolUse hook for Bash commands — blocks git commit/push without tests
# Input: JSON on stdin with tool_input.command (Codex Bash payload)
# Output: JSON on stdout with decision:block to deny, or empty to allow

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .command // empty')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROOF_FILE="${VISUALHUD_SDLC_PROOF_FILE:-$REPO_ROOT/.codex-sdlc/proof/full-suite.sha256}"

current_staged_hash() {
  git -C "$REPO_ROOT" diff --cached --binary 2>/dev/null | LC_ALL=C LANG=C shasum -a 256 | awk '{print $1}'
}

proof_is_current() {
  local expected actual
  [ -f "$PROOF_FILE" ] || return 1
  expected=$(tr -d '[:space:]' < "$PROOF_FILE")
  actual=$(current_staged_hash)
  [ -n "$expected" ] && [ "$expected" = "$actual" ]
}

is_git_subcommand() {
  local subcommand="$1"
  printf '%s' "$COMMAND" | grep -qE "(^|[[:space:]])((/usr/bin/|/bin/)?git)([[:space:]][^[:space:]]+)*[[:space:]]${subcommand}([[:space:]]|$)"
}

if printf '%s' "$COMMAND" | grep -qE '^[[:space:]]*((/usr/bin/|/bin/)?(bash|zsh|sh|dash|ksh|fish))( [[:space:]]*(-[[:alnum:]-]+))*[[:space:]]*$'; then
  echo '{"decision":"block","reason":"SDLC GUARD: Do not bypass checks through an interactive shell. Run the exact command directly so commit/push hooks can inspect it."}'
  exit 0
fi

if is_git_subcommand "commit"; then
  if proof_is_current; then
    exit 0
  fi
  echo '{"decision":"block","reason":"TDD CHECK: Did you run tests before committing? Run your full test suite first. ALL tests must pass."}'
  exit 0
fi

if is_git_subcommand "push"; then
  if proof_is_current; then
    exit 0
  fi
  echo '{"decision":"block","reason":"REVIEW CHECK: Did you self-review your changes and run all tests before pushing?"}'
  exit 0
fi
