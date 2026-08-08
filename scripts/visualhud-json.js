#!/usr/bin/env node
"use strict";

const fs = require("fs");
const crypto = require("crypto");

function readStdin() {
  return fs.readFileSync(0, "utf8");
}

function parseJson(text, fallback = null) {
  try {
    return JSON.parse(text || "null");
  } catch (_error) {
    return fallback;
  }
}

function readJsonFile(file) {
  return parseJson(fs.readFileSync(file, "utf8"), {});
}

function compact(value) {
  process.stdout.write(JSON.stringify(value));
}

function line(value) {
  if (value !== undefined && value !== null) {
    process.stdout.write(String(value));
  }
  process.stdout.write("\n");
}

function getPath(value, path) {
  let current = value;
  for (const part of path.split(".")) {
    if (current == null || typeof current !== "object" || !(part in current)) {
      return undefined;
    }
    current = current[part];
  }
  return current;
}

function numberValue(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value.replace(/%$/, ""));
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function themeState(theme, state, countArg) {
  if (state !== "progress") {
    return theme[state] || null;
  }

  const count = Number(countArg || 0);
  const stages = Array.isArray(theme.stages) ? theme.stages : [];
  if (stages.length === 0) return null;

  let index = stages.findIndex((stage) => stage.max == null || count <= stage.max);
  if (index < 0) index = stages.length - 1;

  const stage = { ...stages[index] };
  const start = index === 0 ? 1 : (stages[index - 1].max || 0) + 1;
  const shades = Array.isArray(stage.shades) ? stage.shades : [];

  if (shades.length > 1) {
    let span;
    if ((stage.max || 999999) >= 999999) {
      if (index === 0) {
        span = shades.length * 20;
      } else {
        const previousMax = stages[index - 1].max || start - 1;
        const previousStart = index <= 1 ? 1 : (stages[index - 2].max || 0) + 1;
        span = (previousMax - previousStart + 1) * shades.length;
      }
    } else {
      span = stage.max - start + 1;
    }

    const shadeIndex = clamp(Math.floor(((count - start) * shades.length) / span), 0, shades.length - 1);
    stage.color = shades[shadeIndex];
    stage.active_shade = shadeIndex + 1;

    if (Array.isArray(stage.shade_sprites) && stage.shade_sprites.length > shadeIndex) {
      stage.base_sprite = stage.sprite;
      stage.sprite = stage.shade_sprites[shadeIndex];
    }
  }

  return stage;
}

function progressBar(theme, stageArg) {
  const limit = Array.isArray(theme.progress_bar) ? theme.progress_bar.length : 0;
  const max = limit > 0 ? limit : Number(stageArg || 0);
  const stage = Number(stageArg || 0);
  let output = "";
  for (let index = 0; index < stage && index < max; index += 1) {
    output += (theme.progress_bar && theme.progress_bar[index]) || "\u25a0";
  }
  return output;
}

function isReviewPayload(payload) {
  const fields = [
    payload.tool_name,
    getPath(payload, "tool_input.command"),
    getPath(payload, "tool_input.description"),
    getPath(payload, "tool_input.prompt"),
    getPath(payload, "tool_input.task"),
    payload.description,
    payload.prompt,
    payload.message,
    payload.last_assistant_message,
    payload.task,
    payload.title,
  ];
  const text = fields.filter((value) => typeof value === "string").join(" ");
  const toolName = String(payload.tool_name || "").toLowerCase();
  return (
    /(code[- ]?review|coder[- ]?review|\/code-review|reviewing[ +]+shipping|review[ +]+ship|codex review|claude review|cross-model review|pull request review|pr review|review deliverables|review round|ship review|reviewer|review v[0-9])/i.test(text) ||
    (toolName === "task" && /review/i.test(text)) ||
    (toolName === "bash" && /((codex|claude)[\s\S]{0,240}review|review[\s\S]{0,240}(codex|claude))/i.test(text))
  );
}

function contextPercentFromJson(payload) {
  const directPaths = [
    "context_used_percent",
    "context_percent",
    "context.used_percent",
    "context.percent_used",
    "context_usage.used_percent",
    "context_usage.percent_used",
    "token_usage.context_used_percent",
    "info.context_used_percent",
    "payload.info.context_used_percent",
  ];
  for (const path of directPaths) {
    const value = numberValue(getPath(payload, path));
    if (value !== undefined) return Math.floor(value);
  }

  const tokenPairs = [
    ["info.last_token_usage.total_tokens", "info.model_context_window"],
    ["payload.info.last_token_usage.total_tokens", "payload.info.model_context_window"],
    ["token_count.info.last_token_usage.total_tokens", "token_count.info.model_context_window"],
    ["token_usage.last_token_usage.total_tokens", "token_usage.model_context_window"],
    ["last_token_usage.total_tokens", "model_context_window"],
  ];
  for (const [tokensPath, windowPath] of tokenPairs) {
    const tokens = getPath(payload, tokensPath);
    const window = getPath(payload, windowPath);
    if (typeof tokens === "number" && typeof window === "number" && window > 0) {
      return Math.floor((tokens * 100) / window);
    }
  }
  return undefined;
}

function contextPercentFromSessionFile(file) {
  if (!file || !fs.existsSync(file)) return undefined;
  const lines = fs.readFileSync(file, "utf8").trimEnd().split(/\r?\n/).slice(-200);
  let percent;
  for (const lineText of lines) {
    const entry = parseJson(lineText, null);
    const info = getPath(entry || {}, "payload.info");
    if (entry && entry.type === "event_msg" && getPath(entry, "payload.type") === "token_count" && info) {
      const tokens = getPath(info, "last_token_usage.total_tokens");
      const window = info.model_context_window;
      if (typeof tokens === "number" && typeof window === "number" && window > 0) {
        percent = Math.floor((tokens * 100) / window);
      }
    }
  }
  return percent;
}

function transcriptTokenTotal(file) {
  if (!file || !fs.existsSync(file)) return undefined;
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
  let total = 0;
  for (const lineText of lines) {
    if (!lineText.trim()) continue;
    const entry = parseJson(lineText, null);
    if (!entry || entry.type !== "assistant") continue;
    const usage = getPath(entry, "message.usage") || {};
    total += Number(usage.input_tokens || 0);
    total += Number(usage.cache_creation_input_tokens || 0);
    total += Number(usage.cache_read_input_tokens || 0);
    total += Number(usage.output_tokens || 0);
  }
  return total;
}

function contextAlert(theme, percentArg) {
  const percent = Number(percentArg);
  if (!Number.isFinite(percent)) return null;
  const alerts = theme.context_alerts || {};
  const cfg = (level) => alerts[level] || {};
  const build = (level, fallbackMin, fallbackBadge, fallbackName, fallbackColor) => ({
    ...cfg(level),
    level,
    percent,
    min_percent: cfg(level).min_percent ?? fallbackMin,
    badge: cfg(level).badge ?? fallbackBadge,
    name: cfg(level).name ?? fallbackName,
    color: cfg(level).color ?? fallbackColor,
  });

  if (percent >= (cfg("critical").min_percent ?? 85)) {
    return build("critical", 85, "CTX!", "Context Critical", [255, 45, 45]);
  }
  if (percent >= (cfg("warning").min_percent ?? 70)) {
    return build("warning", 70, "CTX", "Context High", [255, 190, 40]);
  }
  return null;
}

function mergeCodexHooks(existing, command) {
  const data = existing && typeof existing === "object" ? existing : {};
  data.hooks = data.hooks && typeof data.hooks === "object" ? data.hooks : {};
  const hook = { type: "command", command };

  const hasVisualHud = (name) => {
    const groups = Array.isArray(data.hooks[name]) ? data.hooks[name] : [];
    return groups.some((group) =>
      (Array.isArray(group.hooks) ? group.hooks : []).some((item) => String(item.command || "").includes("visualhud-codex.sh")),
    );
  };

  const addMatcher = (name) => {
    if (!hasVisualHud(name)) {
      data.hooks[name] = [...(Array.isArray(data.hooks[name]) ? data.hooks[name] : []), { matcher: "*", hooks: [hook] }];
    }
  };
  const addPlain = (name) => {
    if (!hasVisualHud(name)) {
      data.hooks[name] = [...(Array.isArray(data.hooks[name]) ? data.hooks[name] : []), { hooks: [hook] }];
    }
  };

  const removeVisualHud = (name) => {
    const groups = Array.isArray(data.hooks[name]) ? data.hooks[name] : [];
    const retained = groups
      .map((group) => ({
        ...group,
        hooks: (Array.isArray(group.hooks) ? group.hooks : []).filter(
          (item) => !String(item.command || "").includes("visualhud-codex.sh"),
        ),
      }))
      .filter((group) => group.hooks.length > 0);

    if (retained.length > 0) {
      data.hooks[name] = retained;
    } else {
      delete data.hooks[name];
    }
  };

  addMatcher("PreToolUse");
  addMatcher("PermissionRequest");
  addMatcher("PostToolUse");
  addPlain("UserPromptSubmit");
  addPlain("Stop");
  addMatcher("SessionStart");
  addMatcher("PreCompact");
  addMatcher("PostCompact");
  addMatcher("SubagentStart");
  addMatcher("SubagentStop");
  removeVisualHud("TaskCompleted");
  removeVisualHud("CwdChanged");
  removeVisualHud("PostToolUseFailure");
  return data;
}

function mergeClaudeHooks(existing, command) {
  const data = existing && typeof existing === "object" ? existing : {};
  data.hooks = data.hooks && typeof data.hooks === "object" ? data.hooks : {};
  const hook = { type: "command", command };

  const hasVisualHud = (name) => {
    const groups = Array.isArray(data.hooks[name]) ? data.hooks[name] : [];
    return groups.some((group) =>
      (Array.isArray(group.hooks) ? group.hooks : []).some((item) => String(item.command || "").includes("visualhud-claude.sh")),
    );
  };

  const addMatcher = (name) => {
    if (!hasVisualHud(name)) {
      data.hooks[name] = [...(Array.isArray(data.hooks[name]) ? data.hooks[name] : []), { matcher: "*", hooks: [hook] }];
    }
  };
  const addPlain = (name) => {
    if (!hasVisualHud(name)) {
      data.hooks[name] = [...(Array.isArray(data.hooks[name]) ? data.hooks[name] : []), { hooks: [hook] }];
    }
  };

  addMatcher("PreToolUse");
  addMatcher("Notification");
  addPlain("UserPromptSubmit");
  addPlain("Stop");
  addPlain("StopFailure");
  addPlain("TaskCompleted");
  addPlain("CwdChanged");
  addMatcher("SessionStart");
  addMatcher("PreCompact");
  addMatcher("PostCompact");
  addMatcher("SubagentStart");
  addMatcher("SubagentStop");
  addMatcher("PostToolUseFailure");
  return data;
}

function hasFailedToolResponse(value) {
  if (value == null || typeof value !== "object") return false;
  if (value.isError === false || value.is_error === false) return false;
  if (typeof value.exit_code === "number" && value.exit_code !== 0) return true;
  if (value.isError === true || value.is_error === true || value.success === false || value.ok === false) return true;
  if (typeof value.status === "string" && /^(error|failed|failure)$/i.test(value.status)) return true;
  return false;
}

function hasSuccessfulToolResponse(value) {
  if (value == null || typeof value !== "object") return false;
  if (typeof value.exit_code === "number") return value.exit_code === 0;
  if (value.isError === false || value.is_error === false) return true;
  if (value.success === true || value.ok === true) return true;
  if (typeof value.status === "string") return /^(ok|success|succeeded|completed)$/i.test(value.status);
  return Array.isArray(value.content);
}

function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value == null || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.keys(value).sort().map((key) => [key, canonicalValue(value[key])]),
  );
}

function permissionKey(payload) {
  const toolInput = payload.tool_input && typeof payload.tool_input === "object" ? { ...payload.tool_input } : {};
  delete toolInput.description;
  const identity = JSON.stringify(canonicalValue([payload.turn_id || "", payload.tool_name || "", toolInput]));
  return `request:${crypto.createHash("sha256").update(identity).digest("hex").slice(0, 24)}`;
}

function codexSubcommand(words) {
  const optionsWithValues = new Set([
    "-a", "--add-dir", "--ask-for-approval", "-c", "--cd", "--config", "-C",
    "--disable", "--enable", "-i", "--image", "--local-provider", "-m", "--model",
    "-p", "--profile", "-s", "--sandbox",
  ]);

  for (let index = 1; index < words.length; index += 1) {
    const word = String(words[index] || "");
    if (word === "--") return String(words[index + 1] || "").toLowerCase();
    if (!word.startsWith("-")) return word.toLowerCase();

    const option = word.split("=", 1)[0];
    if (!word.includes("=") && optionsWithValues.has(option)) index += 1;
  }
  return "";
}

function isDirectForegroundReviewPayload(payload) {
  const command = getPath(payload, "tool_input.command");
  if (typeof command !== "string") return false;

  const words = [];
  let word = "";
  let quote = "";
  let escaping = false;
  for (let index = 0; index < command.length; index += 1) {
    const char = command[index];
    if (escaping) {
      word += char;
      escaping = false;
      continue;
    }
    if (char === "\\" && quote !== "'") {
      escaping = true;
      continue;
    }
    if (quote !== "") {
      if (char === quote) {
        quote = "";
      } else {
        word += char;
      }
      continue;
    }
    if (char === "'" || char === '"') {
      quote = char;
      continue;
    }
    if (char === "#" && (index === 0 || /\s/.test(command[index - 1]))) {
      break;
    }
    if (/[&|;()<`\r\n]/.test(char)) return false;
    if (/\s/.test(char)) {
      if (word !== "") {
        words.push(word);
        word = "";
      }
      continue;
    }
    word += char;
  }
  if (escaping || quote !== "") return false;
  if (word !== "") words.push(word);

  const executable = String(words[0] || "").split(/[\\/]/).pop().toLowerCase();
  const directReviewSubcommand = words.slice(1).some((value) => value.toLowerCase() === "review");
  const directCodexExecReview = executable === "codex"
    && codexSubcommand(words) === "exec"
    && isReviewPayload(payload);
  return (executable === "codex" || executable === "claude") && (directReviewSubcommand || directCodexExecReview);
}

function codexPayload(payload) {
  switch (payload.hook_event_name || "") {
    case "PreToolUse":
      return { ...payload, permission_key: permissionKey(payload) };
    case "PostToolUseFailure":
    case "UserPromptSubmit":
    case "Stop":
    case "TaskCompleted":
    case "PreCompact":
    case "PostCompact":
    case "SubagentStart":
    case "SubagentStop":
      return payload;
    case "PostToolUse":
      if (hasFailedToolResponse(payload.tool_response)) {
        const reviewFailure = isReviewPayload(payload);
        return {
          ...payload,
          hook_event_name: "PostToolUseFailure",
          source_event: "PostToolUse",
          rollback_activity: !reviewFailure && payload.permission_mode !== "plan",
          review_failure: reviewFailure,
          permission_key: permissionKey(payload),
        };
      }
      return hasSuccessfulToolResponse(payload.tool_response) && isReviewPayload(payload) && isDirectForegroundReviewPayload(payload)
        ? { ...payload, hook_event_name: "TaskCompleted", source_event: "PostToolUse", permission_key: permissionKey(payload) }
        : { ...payload, permission_key: permissionKey(payload) };
    case "SessionStart":
      return {
        hook_event_name: "Stop",
        session_id: payload.session_id || "",
        source_event: "SessionStart",
        start_source: payload.source || payload.start_source || "",
      };
    case "PermissionRequest":
      return {
        hook_event_name: "Notification",
        notification_type: "permission_prompt",
        message: getPath(payload, "tool_input.description") || "Codex is requesting permission",
        session_id: payload.session_id || "",
        turn_id: payload.turn_id || "",
        tool_name: payload.tool_name || "",
        tool_input: payload.tool_input || {},
        permission_key: permissionKey(payload),
      };
    default:
      return null;
  }
}

function themeLegend(theme) {
  const states = [
    ["WORKING", "working"],
    ["PLAN", "plan"],
    ["REVIEW", "review"],
    ["CHECK", "permission"],
    ["HITL", "blocked"],
    ["ERROR", "error"],
    ["DONE", "done"],
    ["IDLE", "idle"],
  ];
  return states
    .filter(([, key]) => theme[key] && typeof theme[key] === "object")
    .map(([label, key]) => {
      const state = theme[key];
      return `${label}\t${state.badge || ""}\t${state.name || ""}`.trimEnd();
    })
    .join("\n");
}

function claudePayload(payload) {
  const allowed = new Set([
    "PreToolUse",
    "PostToolUse",
    "PostToolUseFailure",
    "Notification",
    "UserPromptSubmit",
    "Stop",
    "StopFailure",
    "TaskCompleted",
    "CwdChanged",
    "SessionStart",
    "PreCompact",
    "PostCompact",
    "SubagentStart",
    "SubagentStop",
  ]);
  return allowed.has(payload.hook_event_name || "") ? payload : null;
}

function calibrationPayload(step) {
  const kind = step.kind || "";
  let count = 0;
  let payload;
  switch (kind) {
    case "working":
      payload = { hook_event_name: "PreToolUse", tool_name: "Calibration", session_id: "visualhud-calibration" };
      break;
    case "stage":
    case "stage-shade":
      count = Number(step.trigger_count || 0);
      payload = { hook_event_name: "PreToolUse", tool_name: "Calibration", session_id: "visualhud-calibration" };
      break;
    case "context":
      count = Number(step.trigger_count || 0);
      payload = {
        hook_event_name: "PreToolUse",
        tool_name: "Calibration",
        session_id: "visualhud-calibration",
        context_used_percent: Number(step.context_percent || 0),
      };
      break;
    case "blocked":
      payload = {
        hook_event_name: "Notification",
        notification_type: "permission_prompt",
        message: "VisualHUD calibration",
        session_id: "visualhud-calibration",
      };
      break;
    case "permission":
      payload = {
        hook_event_name: "Notification",
        notification_type: "permission_check",
        message: "VisualHUD calibration",
        session_id: "visualhud-calibration",
      };
      break;
    case "review":
      payload = {
        hook_event_name: "PreToolUse",
        tool_name: "Bash",
        tool_input: { command: "codex review --uncommitted" },
        session_id: "visualhud-calibration",
      };
      break;
    case "done":
      payload = { hook_event_name: "Stop", session_id: "visualhud-calibration" };
      break;
    case "idle":
      payload = { hook_event_name: "Notification", notification_type: "idle_prompt", session_id: "visualhud-calibration" };
      break;
    case "error":
      payload = { hook_event_name: "StopFailure", session_id: "visualhud-calibration" };
      break;
    case "plan":
      payload = {
        hook_event_name: "PreToolUse",
        tool_name: "Calibration",
        session_id: "visualhud-calibration",
        permission_mode: "plan",
      };
      break;
    case "compacting":
      payload = { hook_event_name: "PreCompact", session_id: "visualhud-calibration", trigger: "calibration" };
      break;
    case "subagent":
      payload = {
        hook_event_name: "SubagentStart",
        session_id: "visualhud-calibration",
        agent_type: "Calibration",
        agent_id: "visualhud-calibration",
      };
      break;
    default:
      payload = null;
  }
  if (!payload) return null;
  return [kind, count, JSON.stringify(payload)].join("\t");
}

function padStep(value) {
  const text = String(value);
  return text.length === 1 ? `0${text}` : text;
}

function calibrationLabel(step) {
  const color = Array.isArray(step.color) ? step.color.join("-") : "";
  let label = `[${padStep(step.step)}/${padStep(step.total)}] ${(step.badge || "-")} ${step.name || ""}`;
  label += ` | kind=${step.kind || ""}`;
  label += ` | progress=${step.progress_bar || ""}`;
  label += ` | sprite=${step.sprite || ""}`;
  label += ` | color=${color}`;
  if (step.trigger_count) label += ` | count=${step.trigger_count}`;
  if (step.kind === "context") label += ` | context overlay ${step.context_percent}%`;
  return label;
}

function normalizeWindowsPath(value) {
  if (!value) return "";
  const text = String(value);
  const match = text.match(/^\/([a-zA-Z])\/(.*)$/);
  if (match) {
    return `${match[1].toUpperCase()}:/${match[2]}`;
  }
  return text.replace(/\\/g, "/");
}

function weztermState(args) {
  const [
    title,
    contextTitle,
    spritePath,
    color,
    tintColor,
    stage,
    stateKind,
    progressPercent,
    badge,
    name,
    project,
  ] = args;
  return Buffer.from(
    JSON.stringify({
      title: title || "",
      context_title: contextTitle || "",
      sprite_path: normalizeWindowsPath(spritePath || ""),
      color: color || "",
      tint_color: tintColor || "",
      stage: stage || "",
      state_kind: stateKind || "",
      progress_percent: Number(progressPercent || 0),
      badge: badge || "",
      name: name || "",
      project: project || "",
    }),
    "utf8",
  ).toString("base64");
}

const command = process.argv[2];

try {
  switch (command) {
    case "field": {
      const payload = parseJson(readStdin(), {});
      const value = getPath(payload, process.argv[3] || "");
      line(value ?? "");
      break;
    }
    case "event-name":
      line(parseJson(readStdin(), {}).hook_event_name || "");
      break;
    case "theme-display-name": {
      const theme = readJsonFile(process.argv[3]);
      line(theme.name || process.argv[4] || "");
      break;
    }
    case "theme-legend": {
      const theme = readJsonFile(process.argv[3]);
      line(themeLegend(theme));
      break;
    }
    case "progress-bar": {
      const theme = readJsonFile(process.argv[3]);
      process.stdout.write(progressBar(theme, process.argv[4]));
      break;
    }
    case "progress-bar-length": {
      const theme = readJsonFile(process.argv[3]);
      line(Array.isArray(theme.progress_bar) ? theme.progress_bar.length : 0);
      break;
    }
    case "state": {
      const theme = readJsonFile(process.argv[3]);
      compact(themeState(theme, process.argv[4], process.argv[5]));
      break;
    }
    case "stage-index": {
      const theme = readJsonFile(process.argv[3]);
      const count = Number(process.argv[4] || 0);
      const stages = Array.isArray(theme.stages) ? theme.stages : [];
      let index = stages.findIndex((stage) => stage.max == null || count <= stage.max);
      if (index < 0) index = Math.max(0, stages.length - 1);
      line(index);
      break;
    }
    case "state-fields": {
      const state = parseJson(readStdin(), {});
      const color = Array.isArray(state.color) ? state.color : ["", "", ""];
      line([color[0] ?? "", color[1] ?? "", color[2] ?? "", state.sprite || "", state.badge || "", state.name || "", state.stage ?? ""].join("\x1f"));
      break;
    }
    case "review-payload": {
      process.exit(isReviewPayload(parseJson(readStdin(), {})) ? 0 : 1);
      break;
    }
    case "context-percent-json": {
      const percent = contextPercentFromJson(parseJson(readStdin(), {}));
      line(percent ?? "");
      break;
    }
    case "context-percent-session": {
      line(contextPercentFromSessionFile(process.argv[3]) ?? "");
      break;
    }
    case "transcript-token-total": {
      line(transcriptTokenTotal(process.argv[3]) ?? "");
      break;
    }
    case "context-alert": {
      const theme = readJsonFile(process.argv[3]);
      const alert = contextAlert(theme, process.argv[4]);
      if (alert) compact(alert);
      break;
    }
    case "alert-fields": {
      const alert = parseJson(readStdin(), {});
      line([alert.level || "", alert.percent ?? "", alert.badge || "", alert.name || ""].join("\x1f"));
      break;
    }
    case "merge-codex-hooks": {
      const file = process.argv[3];
      const existing = fs.existsSync(file) ? readJsonFile(file) : { hooks: {} };
      process.stdout.write(`${JSON.stringify(mergeCodexHooks(existing, process.argv[4] || ""), null, 2)}\n`);
      break;
    }
    case "merge-claude-hooks": {
      const file = process.argv[3];
      const existing = fs.existsSync(file) ? readJsonFile(file) : { hooks: {} };
      process.stdout.write(`${JSON.stringify(mergeClaudeHooks(existing, process.argv[4] || ""), null, 2)}\n`);
      break;
    }
    case "codex-payload": {
      const payload = codexPayload(parseJson(readStdin(), {}));
      if (!payload) process.exit(3);
      compact(payload);
      break;
    }
    case "claude-payload": {
      const payload = claudePayload(parseJson(readStdin(), {}));
      if (!payload) process.exit(3);
      compact(payload);
      break;
    }
    case "calibration-payload": {
      const payload = calibrationPayload(parseJson(readStdin(), {}));
      if (!payload) process.exit(3);
      line(payload);
      break;
    }
    case "calibration-label":
      line(calibrationLabel(parseJson(readStdin(), {})));
      break;
    case "wezterm-state":
      process.stdout.write(weztermState(process.argv.slice(3)));
      break;
    default:
      console.error(`Unknown visualhud-json command: ${command || ""}`);
      process.exit(2);
  }
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
