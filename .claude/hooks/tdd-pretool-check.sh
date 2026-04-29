#!/bin/bash
# PreToolUse hook - TDD enforcement before editing source files
# Fires before Write/Edit/MultiEdit tools

# Read the tool input (JSON with file_path, content, etc.)
TOOL_INPUT=$(cat)

# Extract the file path being edited (requires jq)
FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.tool_input.file_path // empty')

# VisualHUD: source files are .sh and .py at root level
# Skip test files and config files
if [[ "$FILE_PATH" == *.sh || "$FILE_PATH" == *.py ]] && \
   [[ "$FILE_PATH" != *test* ]] && \
   [[ "$FILE_PATH" != *spec* ]] && \
   [[ "$FILE_PATH" != *SKILL* ]] && \
   [[ "$FILE_PATH" != *hook* ]]; then
  cat << 'EOF'
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "TDD CHECK: Are you writing IMPLEMENTATION before a FAILING TEST? If yes, STOP. Write the test first (TDD RED), then implement (TDD GREEN)."}}
EOF
fi

# No output = allow the tool to proceed
