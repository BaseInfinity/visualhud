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

function isFullWidthCodePoint(codePoint) {
  return codePoint >= 0x1100 && (
    codePoint <= 0x115f
    || codePoint === 0x2329
    || codePoint === 0x232a
    || (codePoint >= 0x2e80 && codePoint <= 0xa4cf && codePoint !== 0x303f)
    || (codePoint >= 0xac00 && codePoint <= 0xd7a3)
    || (codePoint >= 0xf900 && codePoint <= 0xfaff)
    || (codePoint >= 0xfe10 && codePoint <= 0xfe19)
    || (codePoint >= 0xfe30 && codePoint <= 0xfe6f)
    || (codePoint >= 0xff00 && codePoint <= 0xff60)
    || (codePoint >= 0xffe0 && codePoint <= 0xffe6)
    || (codePoint >= 0x20000 && codePoint <= 0x3fffd)
  );
}

function displayWidth(text) {
  const segments = new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(String(text || ""));
  let width = 0;
  for (const { segment } of segments) {
    if (/^[\u{1f1e6}-\u{1f1ff}]{2}$/u.test(segment)
      || /^[#*0-9]\ufe0f?\u20e3$/u.test(segment)
      || /\p{Extended_Pictographic}/u.test(segment)) {
      width += 2;
      continue;
    }
    const visible = [...segment].find((char) => !/[\p{Mark}\u200d\ufe0e\ufe0f]/u.test(char));
    if (!visible) continue;
    const codePoint = visible.codePointAt(0);
    if (codePoint < 0x20 || (codePoint >= 0x7f && codePoint < 0xa0)) continue;
    width += isFullWidthCodePoint(codePoint) ? 2 : 1;
  }
  return width;
}

function firstFittingText(widthArg, candidates) {
  const width = Number(widthArg || 0);
  if (!Number.isFinite(width) || width <= 0) return candidates[0] || "";
  return candidates.find((candidate) => displayWidth(candidate) <= width)
    || candidates[candidates.length - 1]
    || "";
}

const JOURNEY_PROFILES = {
  "codex-default": [
    ["understand", "UNDERSTAND"],
    ["plan", "PLAN"],
    ["implement", "IMPLEMENT"],
    ["verify", "VERIFY"],
    ["review", "REVIEW"],
    ["done", "DONE"],
  ],
  sdlc: [
    ["intake", "INTAKE"],
    ["discovery", "DISCOVERY"],
    ["plan", "PLAN"],
    ["tdd_red", "TDD RED"],
    ["implement", "IMPLEMENT"],
    ["implemented", "IMPLEMENTED"],
    ["targeted_test", "TARGETED TEST"],
    ["full_test", "FULL TEST"],
    ["self_review", "SELF REVIEW"],
    ["final_review", "FINAL REVIEW"],
    ["proof", "PROOF"],
    ["done", "DONE"],
  ],
  release: [
    ["intake", "INTAKE"],
    ["discovery", "DISCOVERY"],
    ["plan", "PLAN"],
    ["tdd_red", "TDD RED"],
    ["implement", "IMPLEMENT"],
    ["implemented", "IMPLEMENTED"],
    ["targeted_test", "TARGETED TEST"],
    ["full_test", "FULL TEST"],
    ["self_review", "SELF REVIEW"],
    ["final_review", "FINAL REVIEW"],
    ["proof", "PROOF"],
    ["ci", "CI"],
    ["publish", "PUBLISH"],
    ["smoke", "SMOKE"],
    ["done", "DONE"],
  ],
};

function journeyProfile(name) {
  const selected = JOURNEY_PROFILES[name] || JOURNEY_PROFILES["codex-default"];
  return selected.map(([id, label], index) => ({ id, label, index: index + 1 }));
}

function journeyTransition(profileName, currentArg, checkpointArg, outcomeArg, generationArg = 0) {
  const profile = journeyProfile(profileName);
  const ids = profile.map((checkpoint) => checkpoint.id);
  const fallback = ids[0];
  const current = ids.includes(currentArg) ? currentArg : fallback;
  const coarseCheckpointMap = {
    intake: "understand",
    discovery: "understand",
    tdd_red: "implement",
    implemented: "implement",
    targeted_test: "verify",
    full_test: "verify",
    self_review: "review",
    final_review: "review",
    proof: "verify",
    ci: "verify",
  };
  const mappedCheckpoint = profileName === "codex-default" ? coarseCheckpointMap[checkpointArg] : "";
  const checkpoint = ids.includes(checkpointArg)
    ? checkpointArg
    : (ids.includes(mappedCheckpoint) ? mappedCheckpoint : current);
  const outcome = String(outcomeArg || "started").toLowerCase();
  const generation = Math.max(0, Number.parseInt(generationArg, 10) || 0);
  const currentIndex = ids.indexOf(current);
  const checkpointIndex = ids.indexOf(checkpoint);
  let next = current;

  if (outcome === "expected_failure" || outcome === "red") {
    next = checkpoint === "tdd_red" ? checkpoint : current;
  } else if (outcome === "transient" || outcome === "preserved") {
    next = current;
  } else if (outcome === "invalidated") {
    next = checkpointIndex < currentIndex ? checkpoint : current;
  } else if (outcome === "failed" || outcome === "finding") {
    const rollback = {
      tdd_red: "implement",
      verify: "implement",
      review: "implement",
      targeted_test: "implement",
      full_test: "implement",
      self_review: "implement",
      final_review: "implement",
      proof: "implement",
      ci: ids.includes("full_test") ? "full_test" : "verify",
      publish: ids.includes("ci") ? "ci" : current,
      smoke: ids.includes("publish") ? "publish" : current,
    };
    next = ids.includes(rollback[checkpoint]) ? rollback[checkpoint] : current;
  } else if (outcome === "passed" || outcome === "completed") {
    const candidate = ids[Math.min(checkpointIndex + 1, ids.length - 1)];
    next = ids.indexOf(candidate) >= currentIndex ? candidate : current;
  } else if (outcome === "started" || outcome === "active") {
    const invalidatingEdit = checkpoint === "tdd_red" || checkpoint === "implement";
    next = checkpointIndex >= currentIndex || invalidatingEdit ? checkpoint : current;
  }

  const index = ids.indexOf(next);
  return {
    profile: JOURNEY_PROFILES[profileName] ? profileName : "codex-default",
    current: next,
    current_index: index + 1,
    total: ids.length,
    generation,
    completed: ids.slice(0, index),
    transition: { from: current, checkpoint, outcome, to: next },
  };
}

function writeJsonAtomic(file, value) {
  const temporary = `${file}.${process.pid}`;
  fs.writeFileSync(temporary, `${JSON.stringify(value)}\n`);
  fs.renameSync(temporary, file);
}

function appendJourneyHistory(file, value) {
  fs.appendFileSync(file, `${JSON.stringify(value)}\n`);
}

function operationMarkerPath(directory, key) {
  const checksum = crypto.createHash("sha256").update(key).digest("hex").slice(0, 24);
  return `${directory}/${checksum}.json`;
}

function rejectActiveJourneyOperations(directory) {
  if (!fs.existsSync(directory)) return;
  for (const name of fs.readdirSync(directory)) {
    const file = `${directory}/${name}`;
    const marker = parseJson(fs.readFileSync(file, "utf8"), {});
    const active = Array.isArray(marker.generations) ? marker.generations.length : 0;
    marker.reject_remaining = Math.max(Number(marker.reject_remaining || 0), active);
    marker.generations = [];
    writeJsonAtomic(file, marker);
  }
}

function journeyApply(profileName, stateFile, historyFile, operationDirectory, themeFile, payload) {
  let state = fs.existsSync(stateFile)
    ? readJsonFile(stateFile)
    : journeyTransition(profileName, "", "", "started");
  if (!fs.existsSync(stateFile)) {
    writeJsonAtomic(stateFile, state);
    appendJourneyHistory(historyFile, state);
  }

  const checkpoint = String(payload.journey_checkpoint || "");
  const outcome = String(payload.journey_outcome || "").toLowerCase();
  const terminalOnly = payload.journey_terminal === true;
  if ((checkpoint && outcome) || terminalOnly) {
    let generation = Math.max(0, Number.parseInt(state.generation, 10) || 0);
    const operationKey = String(payload.journey_operation_key || payload.permission_key || "");
    const invalidating = checkpoint && (outcome === "invalidated"
      || (outcome === "started" && (checkpoint === "tdd_red" || checkpoint === "implement")));
    const terminal = terminalOnly || new Set([
      "active", "passed", "completed", "failed", "finding", "expected_failure", "red",
    ]).has(outcome);

    if (invalidating) {
      generation += 1;
      rejectActiveJourneyOperations(operationDirectory);
    }

    let stale = false;
    if (operationKey) {
      fs.mkdirSync(operationDirectory, { recursive: true });
      const markerFile = operationMarkerPath(operationDirectory, operationKey);
      const marker = fs.existsSync(markerFile) ? readJsonFile(markerFile) : {
        key: operationKey,
        generations: [],
        reject_remaining: 0,
      };
      marker.generations = Array.isArray(marker.generations) ? marker.generations : [];
      marker.reject_remaining = Math.max(0, Number(marker.reject_remaining || 0));

      if (outcome === "started") {
        if (marker.reject_remaining > 0) {
          marker.reject_remaining += 1;
        } else {
          marker.generations.push(generation);
        }
        writeJsonAtomic(markerFile, marker);
      } else if (terminal && fs.existsSync(markerFile)) {
        if (marker.reject_remaining > 0) {
          marker.reject_remaining -= 1;
          stale = true;
        } else if (marker.generations.length > 0) {
          stale = Number(marker.generations.shift()) !== generation;
        }
        if (marker.reject_remaining === 0 && marker.generations.length === 0) {
          fs.unlinkSync(markerFile);
        } else {
          writeJsonAtomic(markerFile, marker);
        }
      }
    }

    if (!stale && checkpoint && outcome) {
      state = journeyTransition(profileName, state.current, checkpoint, outcome, generation);
      writeJsonAtomic(stateFile, state);
      appendJourneyHistory(historyFile, state);
    }
  }

  return journeyRender(readJsonFile(themeFile), profileName, state.current);
}

function journeyCompleteReadOnly(profileName, stateFile, historyFile, themeFile) {
  let state = fs.existsSync(stateFile)
    ? readJsonFile(stateFile)
    : journeyTransition(profileName, "", "", "started");
  const last = state.transition || {};
  const noToolAnswer = state.current === "understand" && last.outcome === "started";
  const successfulDiscovery = state.current === "plan"
    && last.checkpoint === "understand"
    && last.outcome === "passed";
  if (profileName === "codex-default" && (noToolAnswer || successfulDiscovery)) {
    state = journeyTransition(profileName, state.current, "done", "completed", state.generation);
    writeJsonAtomic(stateFile, state);
    appendJourneyHistory(historyFile, state);
  }
  return journeyRender(readJsonFile(themeFile), profileName, state.current);
}

function journeyPayload(profileName, checkpoint, outcome) {
  if (!Object.hasOwn(JOURNEY_PROFILES, profileName)) {
    throw new Error(`Unknown journey profile: ${profileName}`);
  }
  const checkpoints = JOURNEY_PROFILES[profileName].map(([id]) => id);
  if (!checkpoints.includes(checkpoint)) {
    throw new Error(`Unknown ${profileName} checkpoint: ${checkpoint}`);
  }
  const allowedOutcomes = new Set([
    "started", "active", "passed", "completed", "failed", "finding",
    "invalidated", "transient", "preserved", "expected_failure", "red",
  ]);
  const normalizedOutcome = String(outcome || "started").toLowerCase();
  if (!allowedOutcomes.has(normalizedOutcome)) {
    throw new Error(`Unknown journey outcome: ${outcome}`);
  }
  return {
    hook_event_name: "JourneyUpdate",
    journey_profile: profileName,
    journey_checkpoint: checkpoint,
    journey_outcome: normalizedOutcome,
  };
}

function journeyRender(theme, profileName, currentArg) {
  const profile = journeyProfile(profileName);
  const ids = profile.map((checkpoint) => checkpoint.id);
  const index = Math.max(0, ids.indexOf(currentArg));
  const checkpoint = profile[index];
  const done = checkpoint.id === "done";
  const stages = Array.isArray(theme.stages) ? theme.stages : [];
  const progress = Array.isArray(theme.progress_bar) ? theme.progress_bar : [];
  const preDoneCount = Math.max(1, profile.length - 1);
  const stageIndex = Math.min(
    Math.max(0, stages.length - 1),
    Math.floor((index * Math.max(1, stages.length)) / preDoneCount),
  );
  const visual = { ...(done ? (theme.done || {}) : (stages[stageIndex] || theme.working || {})) };
  const filled = [];
  for (let step = 0; step <= index; step += 1) {
    if (step === profile.length - 1) {
      filled.push(progress[progress.length - 1] || "\u25a0");
    } else if (progress.length > 0) {
      const progressIndex = Math.min(progress.length - 1, Math.floor((step * progress.length) / preDoneCount));
      filled.push(progress[progressIndex]);
    } else {
      filled.push("\u25a0");
    }
  }

  const visualName = String(visual.name || "").trim();
  return {
    ...visual,
    name: visualName ? `${checkpoint.label} · ${visualName}` : checkpoint.label,
    stage: index + 1,
    progress_bar: filled.join(""),
    journey_checkpoint: checkpoint.id,
    journey_label: checkpoint.label,
    journey_index: index + 1,
    journey_total: profile.length,
  };
}

function journeyLegend(theme, profileName) {
  const profile = journeyProfile(profileName);
  const resolvedProfile = JOURNEY_PROFILES[profileName] ? profileName : "codex-default";
  const checkpoints = profile.map((checkpoint) => {
    const visual = journeyRender(theme, resolvedProfile, checkpoint.id);
    return [
      "CHECKPOINT",
      `${checkpoint.index}/${profile.length}`,
      checkpoint.label,
      visual.badge || "",
      visual.name || "",
    ].join("\t").trimEnd();
  });
  return [
    `Journey profile: ${resolvedProfile}`,
    ...checkpoints,
    "OVERLAY\tCHECK, HITL, COMPACT, SUBAGENT, transient errors preserve the current checkpoint",
    "ROLLBACK\tFailed tests, review findings, proof failures, and CI regressions clear invalid later checkpoints",
  ].join("\n");
}

function isReviewPayload(payload) {
  const fields = [
    payload.tool_name,
    getPath(payload, "tool_input.command"),
    getPath(payload, "tool_input.cmd"),
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
  const toolName = normalizedToolName(payload.tool_name);
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

function codexVisualHudRegistration(existing) {
  const hooks = existing && typeof existing.hooks === "object" ? existing.hooks : {};
  const registrations = [];

  for (const event of Object.keys(hooks).sort()) {
    const groups = Array.isArray(hooks[event]) ? hooks[event] : [];
    for (const group of groups) {
      const commands = Array.isArray(group.hooks) ? group.hooks : [];
      for (const hook of commands) {
        const command = String(hook.command || "");
        if (!command.includes("visualhud-codex.sh")) continue;
        registrations.push({
          event,
          matcher: String(group.matcher || ""),
          type: String(hook.type || ""),
          command,
        });
      }
    }
  }

  registrations.sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
  return registrations;
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

function hasExplicitRawFailure(value) {
  return /\b(?:process|command|review)\s+failed\b/i.test(value)
    || /\bexited with (?:code|status)\s+[1-9][0-9]*\b/i.test(value)
    || /(?:^|\n)\s*(?:error|fatal):/i.test(value)
    || /(?:^|\n)\s*#\s*fail\s+[1-9][0-9]*(?:\s|$)/i.test(value)
    || /\b[1-9][0-9]*\s+(?:failed|errors?)\b/i.test(value);
}

function hasRawReviewFailureOutsideFindings(value) {
  const text = value.trim();
  if (/^[\[{]/.test(text)) {
    try {
      const parsed = JSON.parse(text);
      if (reviewFindingArrays(parsed).length > 0) return hasStructuredReviewProcessFailure(parsed);
    } catch {
      // Mixed prose/JSON is handled as text so later failure diagnostics remain visible.
    }
  }
  const nonFindingText = value
    .split("\n")
    .filter((line) => !/^\s*(?:[-*]\s*)?\[P[0-3]\]/i.test(line))
    .join("\n");
  return hasExplicitRawFailure(nonFindingText);
}

function rawTestReceiptKind(payload) {
  const words = foregroundShellWords(payload);
  if (!words) return "";
  const executable = String(words[0] || "").split(/[\\/]/).pop().toLowerCase();
  if (packageTestCheckpoint(words) && packageTestCheckpoint(words) !== "non_test") return "package";
  if (isRunAllCommand(words)) return "visualhud";
  if (executable === "node") {
    const nodeTarget = String(words[1] || "").replace(/\\/g, "/").replace(/^\.\//, "");
    if (nodeTarget === "--test") return "node:test";
    if (nodeTarget === "tests/test-pokemon-theme-lifecycle.js") return "node:lifecycle";
    return "";
  }
  if (executable === "pytest" || executable === "py.test") return "pytest";
  if (executable === "cargo" && words[1] === "test") return "cargo";
  if (executable === "go" && words[1] === "test") return "go";
  if (/^(?:bash|sh|zsh)$/.test(executable)) {
    let scriptIndex = 1;
    while (String(words[scriptIndex] || "").startsWith("-")) {
      const option = String(words[scriptIndex] || "");
      if (option === "--") {
        scriptIndex += 1;
        break;
      }
      if (option === "-c" || /^-[^-]*c/.test(option)
        || option === "-s" || /^-[^-]*s/.test(option)
        || /^(?:-o|-O|--init-file|--rcfile)$/.test(option)) return "";
      scriptIndex += 1;
    }
    const script = String(words[scriptIndex] || "").replace(/\\/g, "/").replace(/^\.\//, "").toLowerCase();
    const countedScripts = new Set([
      "tests/test-claude-visualhud.sh",
      "tests/test-codex-git-guard.sh",
      "tests/test-codex-visualhud.sh",
      "tests/test-cooking-status.sh",
      "tests/test-host-renderer-matrix.sh",
      "tests/test-iterm-canary.sh",
      "tests/test-journey-state.sh",
      "tests/test-npm-package.sh",
      "tests/test-npm-release.sh",
      "tests/test-review-workflow.sh",
      "tests/test-state-dir-portability.sh",
      "tests/test-theme-calibration.sh",
      "tests/test-theme-system.sh",
      "tests/test-visualhud-cli.sh",
      "tests/test-visualhud-install.sh",
      "tests/test-visualhud-skills.sh",
    ]);
    if (countedScripts.has(script)) return "shell:count-zero";
    if (script === "tests/test-wezterm-renderer.sh" || script === "tests/test-windows-runtime-no-jq.sh") return "shell:results-pass";
    if (script === "tests/test-visualhud-install-global.sh") return "shell:equal-count";
    if (script === "tests/test-context-overlay.sh") return "shell:context-overlay";
  }
  return "";
}

function hasSuccessfulToolResponse(value, checkpoint = "", payload = {}) {
  if (typeof value === "string") {
    // Codex 0.147 emits PostToolUse output without an exit-status envelope.
    // Reviews carry their own completed finding/clean grammar, while test and
    // proof gates require an unambiguous terminal success line.
    if (checkpoint === "final_review") {
      const reviewOutcome = reviewOutcomeFromResponse(value);
      return Boolean(reviewOutcome) && !hasRawReviewFailureOutsideFindings(value);
    }
    const terminal = value.trimEnd();
    if (checkpoint === "proof") return /(?:^|\n)Wrote SDLC proof:\s+.+$/i.test(terminal);
    if (checkpoint === "full_test" || checkpoint === "targeted_test") {
      const hasCoverageFailure = /(?:^|\n)(?:FAIL Required test coverage of [^\n]+ not reached|ERROR: Coverage failure:)[^\n]*$/im.test(terminal);
      const hasCancelledTap = /(?:^|\n)\s*#\s*cancelled\s+[1-9][0-9]*(?:\s|$)/i.test(terminal);
      const completeTapFooter = /(?:^|\n)\s*#\s*fail\s+0\s*\n(?:\s*#\s*(?:cancelled\s+0|(?:skipped|todo)\s+\d+)\s*\n)*\s*#\s*duration_ms\s+[\d.]+$/i.test(terminal);
      const kind = rawTestReceiptKind(payload);
      if (kind === "pytest" && hasCoverageFailure) return false;
      if (kind === "package" || kind === "visualhud") {
        return /(?:^|\n)=== VisualHUD full suite: PASS ===$/i.test(terminal);
      }
      if (kind === "node:test") {
        return (/(?:^|\n)\s*#\s*fail\s+0$/i.test(terminal) && !hasCancelledTap)
          || completeTapFooter;
      }
      if (kind === "node:lifecycle") return /(?:^|\n)PASS: Pokemon theme lifecycle and engine states are complete and distinct$/i.test(terminal);
      if (kind === "pytest") {
        return /(?:^|\n)={2,}(?![^\n]*\b[1-9][0-9]*\s+(?:failed|errors?)\b)(?![^\n]*\d+\/\d+\s+passed)[^\n]*\b\d+\s+passed\b[^\n]*={2,}$/i.test(terminal)
          || /(?:^|\n)\d+\s+passed(?:,\s+\d+\s+(?:skipped|xfailed|xpassed|deselected|warnings?))*\s+in\s+[\d.]+s$/i.test(terminal);
      }
      if (kind === "cargo") return /(?:^|\n)test result:\s+ok\.[^\n]*$/i.test(terminal);
      if (kind === "go") return /(?:^|\n)(?:ok|\?)\s+\S+(?:\s+(?:[\d.]+s|\(cached\)|\[no test files\]))?$/i.test(terminal);
      if (kind === "shell:count-zero") return /(?:^|\n)=== Results:\s+(\d+)\/\1\s+passed,\s*0\s+failed ===$/i.test(terminal);
      if (kind === "shell:results-pass") return /(?:^|\n)=== Results: PASS ===$/i.test(terminal);
      if (kind === "shell:equal-count") return /(?:^|\n)=== Results:\s+(\d+)\/\1\s+passed ===$/i.test(terminal);
      if (kind === "shell:context-overlay") return /(?:^|\n)All context character overlay tests passed\.$/i.test(terminal);
      return false;
    }
    return false;
  }
  if (value == null || typeof value !== "object") return false;
  if (typeof value.exit_code === "number") return value.exit_code === 0;
  if (value.isError === false || value.is_error === false) return true;
  if (value.success === true || value.ok === true) return true;
  if (typeof value.status === "string") return /^(ok|success|succeeded|completed)$/i.test(value.status);
  return Array.isArray(value.content);
}

function toolResponseText(value) {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return value.map(toolResponseText).filter(Boolean).join("\n");
  if (value == null || typeof value !== "object") return "";
  return ["output", "stdout", "text", "message", "result", "content"]
    .map((key) => toolResponseText(value[key]))
    .filter(Boolean)
    .join("\n");
}

function reviewFindingArrays(value, output = []) {
  if (typeof value === "string") {
    const text = value.trim();
    const candidates = [text, ...text.split(/\r?\n/).map((line) => line.trim())];
    for (const candidate of new Set(candidates)) {
      if (!/^[\[{]/.test(candidate)) continue;
      try {
        const parsed = JSON.parse(candidate);
        if (parsed !== candidate) reviewFindingArrays(parsed, output);
      } catch {
        // Review output may mix prose and JSON; only valid JSON contributes evidence.
      }
    }
    return output;
  }
  if (Array.isArray(value)) {
    value.forEach((item) => reviewFindingArrays(item, output));
    return output;
  }
  if (value == null || typeof value !== "object") return output;
  if (Array.isArray(value.findings)) output.push(value.findings);
  Object.values(value).forEach((item) => reviewFindingArrays(item, output));
  return output;
}

function structuredReviewDocuments(value, output = []) {
  if (typeof value === "string") {
    try {
      structuredReviewDocuments(JSON.parse(value.trim()), output);
    } catch {
      // Only whole-string JSON documents can provide clean structured evidence.
    }
    return output;
  }
  if (Array.isArray(value)) {
    value.forEach((item) => structuredReviewDocuments(item, output));
    return output;
  }
  if (value == null || typeof value !== "object") return output;
  if (Array.isArray(value.findings)) output.push(value);
  Object.values(value).forEach((item) => structuredReviewDocuments(item, output));
  return output;
}

function hasNegativeStructuredReviewEnvelope(value) {
  if (Array.isArray(value)) return value.some(hasNegativeStructuredReviewEnvelope);
  if (value == null || typeof value !== "object") return false;
  const correctness = String(value.overall_correctness ?? value.correctness ?? "");
  if (hasStructuredReviewProcessFailure(value) || /(?:^|\b)(?:patch\s+is\s+)?incorrect(?:\b|$)/i.test(correctness)) return true;
  return Object.values(value).some(hasNegativeStructuredReviewEnvelope);
}

function hasStructuredReviewProcessFailure(value) {
  if (Array.isArray(value)) return value.some(hasStructuredReviewProcessFailure);
  if (value == null || typeof value !== "object") return false;
  const explicitError = value.error != null && value.error !== false && value.error !== ""
    || Array.isArray(value.errors) && value.errors.length > 0;
  if (hasFailedToolResponse(value) || explicitError) return true;
  return Object.values(value).some(hasStructuredReviewProcessFailure);
}

function reviewOutcomeFromResponse(value) {
  const text = toolResponseText(value);
  const structuredDocuments = structuredReviewDocuments(value);
  if (hasStructuredReviewProcessFailure(value)
    || structuredDocuments.some(hasStructuredReviewProcessFailure)) return "";
  if (/(?:^|\n)\s*(?:[-*]\s*)?\[P[0-3]\]/im.test(text)) return "finding";

  const findings = reviewFindingArrays(value);
  if (findings.some((items) => items.length > 0)) return "finding";
  if (structuredDocuments.some((document) => document.findings.length === 0)
    && structuredDocuments.every((document) => !hasNegativeStructuredReviewEnvelope(document))
    && !hasNegativeStructuredReviewEnvelope(value)) return "passed";
  if (/(?:^|\n)[ \t]*(?:no|zero|0)\s+(?:P0-P3\s+)?(?:actionable\s+)?(?:review\s+)?(?:findings|issues)(?:\s+(?:found|identified))?(?:\s+in\s+(?:the\s+)?current\s+diff)?[.!]?[ \t]*(?=$|\n)/i.test(text)) {
    return "passed";
  }
  return "";
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

function journeyOperationKey(payload) {
  const identifier = payload.tool_use_id || payload.tool_call_id || payload.call_id || "";
  return identifier ? `operation:${identifier}` : permissionKey(payload);
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

function foregroundShellSegments(command) {
  if (typeof command !== "string") return null;
  const segments = [];
  let words = [];
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
      const lineEnd = command.indexOf("\n", index);
      if (lineEnd >= 0 && command.slice(lineEnd + 1).trim() !== "") return null;
      break;
    }
    if (char === "&" && command[index + 1] === "&") {
      if (word !== "") words.push(word);
      if (words.length === 0) return null;
      segments.push(words);
      words = [];
      word = "";
      index += 1;
      continue;
    }
    if (char === ">") {
      if (word !== "") {
        words.push(word);
        word = "";
      }
      const redirect = command[index + 1] === ">" ? ">>" : ">";
      words.push(redirect);
      if (redirect === ">>") index += 1;
      continue;
    }
    if (/[&|;()<`\r\n]/.test(char)) return null;
    if (/\s/.test(char)) {
      if (word !== "") {
        words.push(word);
        word = "";
      }
      continue;
    }
    word += char;
  }
  if (escaping || quote !== "") return null;
  if (word !== "") words.push(word);
  if (words.length === 0) return null;
  segments.push(words);
  return segments;
}

function foregroundShellWords(payload) {
  const command = getPath(payload, "tool_input.command") ?? getPath(payload, "tool_input.cmd");
  const segments = foregroundShellSegments(command);
  return segments && segments.length === 1 ? commandWords(segments[0]) : null;
}

function isDirectForegroundProofPayload(payload) {
  const words = foregroundShellWords(payload);
  if (!words) return false;
  const guardPath = String(words[1] || "").replace(/\\/g, "/").replace(/^\.\//, "");
  return guardPath === ".codex/hooks/git-guard.cjs"
    && String(words[0] || "").split(/[\\/]/).pop().toLowerCase() === "node"
    && words.length === 4
    && words[2] === "prove"
    && words[3] === "--reviewed";
}

function hasAuthoritativeRawCompletionPayload(payload, checkpoint) {
  if (typeof payload.tool_response !== "string") return true;
  if (checkpoint === "proof") return isDirectForegroundProofPayload(payload);
  if (checkpoint === "full_test" || checkpoint === "targeted_test") {
    return !isShellCommandPayload(payload) || foregroundShellWords(payload) !== null;
  }
  return true;
}

function commandWords(words) {
  if (!Array.isArray(words)) return [];
  const normalized = [...words];
  const assignment = /^[A-Za-z_][A-Za-z0-9_]*=/;
  while (assignment.test(String(normalized[0] || ""))) normalized.shift();

  const executable = String(normalized[0] || "").split(/[\\/]/).pop().toLowerCase();
  if (executable !== "env") return normalized;
  normalized.shift();
  while (normalized.length > 0) {
    const word = String(normalized[0] || "");
    if (assignment.test(word) || word === "--" || /^--(?:ignore-environment|null)$/.test(word)) {
      normalized.shift();
      continue;
    }
    if (/^(?:-u|-C|-S|--unset|--chdir|--split-string)$/.test(word)) {
      normalized.splice(0, 2);
      continue;
    }
    if (/^(?:--unset|--chdir|--split-string)=/.test(word)) {
      normalized.shift();
      continue;
    }
    break;
  }
  while (assignment.test(String(normalized[0] || ""))) normalized.shift();
  return normalized;
}

function isDirectForegroundReviewPayload(payload) {
  const words = foregroundShellWords(payload);
  if (!words) return false;

  const executable = String(words[0] || "").split(/[\\/]/).pop().toLowerCase();
  const directReviewSubcommand = words.slice(1).some((value) => value.toLowerCase() === "review");
  const directCodexExecReview = executable === "codex"
    && codexSubcommand(words) === "exec"
    && isReviewPayload(payload);
  return (executable === "codex" || executable === "claude") && (directReviewSubcommand || directCodexExecReview);
}

function toolInputText(payload) {
  const input = payload.tool_input;
  if (typeof input === "string") return input;
  if (input == null || typeof input !== "object") return "";
  return ["command", "cmd", "input", "script", "patch", "prompt", "description"]
    .map((key) => input[key])
    .filter((value) => typeof value === "string")
    .join("\n");
}

function planAggregate(payload) {
  const plan = getPath(payload, "tool_input.plan");
  if (!Array.isArray(plan) || plan.length === 0) return "";
  const completed = plan.filter((item) => item && item.status === "completed").length;
  return `Tasks ${completed}/${plan.length}`;
}

function normalizedToolName(value) {
  return String(value || "").toLowerCase().split(/__|\./).pop();
}

function isShellCommandPayload(payload) {
  const toolName = normalizedToolName(payload.tool_name);
  return /^(?:bash|shell|exec_command|run_command|terminal)$/.test(toolName);
}

function packageTestCheckpoint(words) {
  if (!Array.isArray(words) || words.length < 2) return "";
  const normalizedWords = [...words];
  const executable = String(normalizedWords[0] || "").split(/[\\/]/).pop().toLowerCase();
  if (!["npm", "pnpm", "yarn", "bun"].includes(executable)) return "";

  const runner = String(normalizedWords[1] || "").toLowerCase();
  const testIndex = runner === "run" || runner === "run-script" ? 2 : 1;
  const script = String(normalizedWords[testIndex] || "").toLowerCase();
  if (!/^test(?:[:._-][\w.-]+)?$/.test(script)) return "";
  const args = normalizedWords.slice(testIndex + 1);
  const nonExecutingOption = args.some((arg) => {
    const value = String(arg);
    if (value === "-h") return true;
    const match = value.match(/^--(?:help|version|list|listTests|showConfig|collect-only)(?:=(.*))?$/i);
    return Boolean(match) && !/^(?:false|0)$/i.test(match[1] || "");
  });
  if (nonExecutingOption) return "non_test";
  let positional = false;
  let selectionOption = false;
  for (let index = 0; index < args.length; index += 1) {
    const arg = String(args[index] || "");
    if (/^(?:-t|-g|--(?:testPathPatterns?|testNamePattern|runTestsByPath|findRelatedTests|filter|grep|fgrep|spec|project|changedSince|onlyChanged|changed|related))(?:=|$)/i.test(arg)) {
      selectionOption = true;
    }
    if (arg === "--" || arg.startsWith("-")) continue;
    if (/^(?:>|>>)$/.test(arg)) {
      index += 1;
      continue;
    }
    if (/^\d*(?:>|>>).+/.test(arg)) continue;
    positional = true;
  }
  return script === "test" && !positional && !selectionOption ? "full_test" : "targeted_test";
}

function directTestArgs(args, selectionOptions, valueOptions) {
  const positional = [];
  let selected = false;
  for (let index = 0; index < args.length; index += 1) {
    const arg = String(args[index] || "");
    const option = arg.includes("=") ? arg.slice(0, arg.indexOf("=")) : arg;
    if (selectionOptions.test(option)) {
      selected = true;
      if (!arg.includes("=")) index += 1;
      continue;
    }
    if (arg.startsWith("-")) {
      if (valueOptions.test(option) && !arg.includes("=")) index += 1;
      continue;
    }
    positional.push(arg);
  }
  return { positional, selected };
}

function directTestCheckpoint(words) {
  if (!Array.isArray(words) || words.length === 0) return "";
  const executable = String(words[0] || "").split(/[\\/]/).pop().toLowerCase();
  if (/^(?:pytest|py\.test)$/.test(executable)) {
    const { positional, selected } = directTestArgs(
      words.slice(1),
      /^(?:-k|-m|--(?:ignore|ignore-glob|deselect|lf|last-failed|ff|failed-first))$/i,
      /^(?:--maxfail|--tb|--capture|--color|--durations|--durations-min|--junitxml|--junit-prefix|--basetemp|--rootdir|--confcutdir|--import-mode|-o|--override-ini)$/i,
    );
    return !selected && positional.length === 0 ? "full_test" : "targeted_test";
  }
  if (executable === "cargo" && String(words[1] || "").toLowerCase() === "test") {
    const { positional, selected } = directTestArgs(
      words.slice(2),
      /^(?:-p|--(?:package|workspace|exclude|lib|bin|bins|example|examples|test|tests|bench|benches|doc))$/i,
      /^(?:-j|--jobs|--features|--target|--target-dir|--color|--message-format|--manifest-path|--profile|--timings)$/i,
    );
    return !selected && positional.length === 0 ? "full_test" : "targeted_test";
  }
  if (executable === "go" && String(words[1] || "").toLowerCase() === "test") {
    const { positional, selected } = directTestArgs(
      words.slice(2),
      /^(?:-run|-skip|-list)$/i,
      /^(?:-count|-timeout|-parallel|-cpu|-benchtime|-shuffle|-vet|-coverprofile|-covermode|-coverpkg|-exec|-fuzztime|-fuzzminimizetime)$/i,
    );
    return !selected && positional.length === 1 && positional[0] === "./..." ? "full_test" : "targeted_test";
  }
  if (executable === "node" && String(words[1] || "").toLowerCase() === "--test") {
    const { positional, selected } = directTestArgs(
      words.slice(2),
      /^--test-(?:name-pattern|only)$/i,
      /^--test-(?:reporter|reporter-destination|concurrency|timeout)$/i,
    );
    return !selected && positional.length === 0 ? "full_test" : "targeted_test";
  }
  return "";
}

function isRunAllCommand(words) {
  if (!Array.isArray(words) || words.length === 0) return false;
  const executablePath = String(words[0] || "").replace(/\\/g, "/");
  const executable = executablePath.split("/").pop().toLowerCase();
  if (executable === "run-all.sh" && /(?:^|\/)tests\/run-all\.sh$/i.test(executablePath)) {
    return true;
  }
  if (!/^(?:bash|sh|zsh)$/.test(executable)) return false;
  const script = words.slice(1).find((word) => !String(word).startsWith("-"));
  return /(?:^|[\\/])tests[\\/]run-all\.sh$/i.test(String(script || ""));
}

function testCheckpointForCommand(command, words) {
  const boundary = "(?:^|[;&|]\\s*)";
  const packageTest = new RegExp(
    `${boundary}(?:npm|pnpm|yarn|bun)\\s+(?:(?:run|run-script)\\s+)?test(?:[:._-][\\w.-]+)?(?=\\s|$)`,
    "im",
  );
  const directTest = new RegExp(
    `${boundary}(?:pytest|go\\s+test|cargo\\s+test)(?=\\s|$)`,
    "im",
  );
  const shellTest = new RegExp(
    `${boundary}(?:bash|sh|zsh)\\s+(?:-[\\w-]+\\s+)*(?:(?:[^\\s;&|]+/)*tests?/[^\\s;&|]+|(?:[^\\s;&|]+/)*test-[^\\s;&|]+\\.sh)(?=\\s|$)`,
    "im",
  );
  const nodeTest = new RegExp(
    `${boundary}node\\s+(?:--test(?=\\s|$)|[^\\n;&|]*(?:^|[/_.-])(?:test|spec)(?=[/_.-]|$))`,
    "im",
  );
  const packageCheckpoint = packageTestCheckpoint(words);
  if (packageCheckpoint === "non_test") return "";
  if (packageCheckpoint) return packageCheckpoint;
  const directCheckpoint = directTestCheckpoint(words);
  if (directCheckpoint) return directCheckpoint;
  if (isRunAllCommand(words)) return "full_test";
  return packageTest.test(command) || directTest.test(command) || shellTest.test(command) || nodeTest.test(command)
    ? "targeted_test"
    : "";
}

function foregroundTestCheckpoint(command) {
  const segments = foregroundShellSegments(command);
  if (!segments) return "";
  let checkpoint = "";
  for (const words of segments) {
    const normalizedWords = commandWords(words);
    const candidate = testCheckpointForCommand(normalizedWords.join(" "), normalizedWords);
    if (candidate === "full_test") return candidate;
    if (candidate === "targeted_test") checkpoint = candidate;
  }
  return checkpoint;
}

function sourceMutationCheckpoint(command) {
  const text = String(command || "");
  const sourcePath = /(?:^|[\s'"=])((?:\.?\.?\/)*(?:(?:src|lib|app|scripts?|tests?|docs?)\/[^\s'";|&]+|[^\s'";|&]+\.(?:c|cc|cpp|css|go|h|hpp|html|java|js|json|jsx|lua|md|mjs|py|rb|rs|sh|ts|tsx|ya?ml)))/gim;
  const paths = [...text.matchAll(sourcePath)].map((match) => match[1]);
  const hasSourcePath = paths.length > 0;
  const inlineEdit = /(?:^|[;&|]\s*)(?:sed\b[^\n;&|]*(?:\s-i(?:\s|$)|--in-place)|perl\b[^\n;&|]*\s-pi)/im;
  const formatterWrite = /(?:^|[;&|]\s*)(?:(?:npx|pnpm\s+exec|bunx)\s+)?(?:prettier|biome|eslint|clang-format)\b[^\n;&|]*(?:--write|--fix|\s-i\b)|(?:^|[;&|]\s*)(?:gofmt\s+-w|cargo\s+fmt\b)/im;
  const redirectedWrite = /(?:^|[;&|]\s*)(?:cat|printf|echo|tee)\b[^\n;&|]*(?:>|>>)/im;
  const fileMutation = /(?:^|[;&|]\s*)(?:cp|mv|rm|touch|install)\b/im;
  const codegen = /(?:^|[;&|]\s*)(?:npm|pnpm|yarn|bun)\s+(?:(?:run|run-script)\s+)?(?:generate|codegen|gen)(?=\s|$)/im;
  const mutation = (hasSourcePath && (inlineEdit.test(text) || redirectedWrite.test(text) || fileMutation.test(text)))
    || formatterWrite.test(text) || codegen.test(text);
  if (!mutation) return "";
  return paths.length > 0 && paths.every(isTestFilePath) ? "tdd_red" : "implement";
}

function isTestFilePath(file) {
  const normalized = String(file || "").trim().replace(/^['"]|['"]$/g, "").replace(/\\/g, "/");
  return /(?:^|\/)(?:tests?|__tests__)(?:\/|$)/i.test(normalized)
    || /(?:^|[._-])(?:test|spec)\.[^/]+$/i.test(normalized);
}

function patchPayloadFiles(payload) {
  const toolName = normalizedToolName(payload.tool_name);
  if (toolName !== "apply_patch") return [];
  return [...toolInputText(payload).matchAll(/^\*\*\* (?:(?:Add|Update|Delete) File:|Move to:)\s+(.+)$/gm)]
    .map((match) => match[1]);
}

function isJourneyNeutralPath(file) {
  const normalized = String(file || "").trim().replace(/^['"]|['"]$/g, "").replace(/\\/g, "/");
  return /(?:^|\/)\.visualhud\/feedback(?:\/|$)/i.test(normalized);
}

function journeyRelevantPatchFiles(payload) {
  return patchPayloadFiles(payload).filter((file) => !isJourneyNeutralPath(file));
}

function isJourneyNeutralPatchPayload(payload) {
  const files = patchPayloadFiles(payload);
  return files.length > 0 && files.every(isJourneyNeutralPath);
}

function isTestOnlyPatchPayload(payload) {
  const files = journeyRelevantPatchFiles(payload);
  return files.length > 0 && files.every(isTestFilePath);
}

function journeyCheckpointForPayload(payload) {
  if (typeof payload.journey_checkpoint === "string" && payload.journey_checkpoint) {
    return payload.journey_checkpoint;
  }

  const toolName = normalizedToolName(payload.tool_name);
  const text = toolInputText(payload);
  const shellCommand = isShellCommandPayload(payload);
  const foregroundWords = shellCommand ? foregroundShellWords(payload) : [];
  const directForeground = !shellCommand || foregroundWords !== null;
  if (toolName === "update_plan") return "plan";
  if (toolName === "apply_patch") {
    if (isJourneyNeutralPatchPayload(payload)) return "";
    return isTestOnlyPatchPayload(payload) ? "tdd_red" : "implement";
  }
  if (shellCommand && /git-guard\.cjs\s+prove\b/i.test(text)) return "proof";
  if (isReviewPayload(payload) && (!shellCommand || isDirectForegroundReviewPayload(payload))) return "final_review";
  if (shellCommand) {
    const mutationCheckpoint = sourceMutationCheckpoint(text);
    if (mutationCheckpoint) return mutationCheckpoint;
  }
  if (shellCommand) return foregroundTestCheckpoint(text);
  if (!directForeground) return "";
  if (/^(?:read|find|search|open|list_mcp_resources|read_mcp_resource|view_image)$/.test(toolName)) return "discovery";
  return "";
}

function withJourneySignal(result, original) {
  if (!result) return result;
  const checkpoint = journeyCheckpointForPayload(original);
  const aggregate = planAggregate(original) || original.journey_aggregate || "";
  let outcome = original.journey_outcome || "";
  const eventName = original.hook_event_name || "";

  if (!outcome && checkpoint) {
    if (eventName === "PreToolUse") {
      outcome = "started";
    } else if (eventName === "PostToolUse" && hasFailedToolResponse(original.tool_response)) {
      outcome = "failed";
    } else if (eventName === "PostToolUse"
      && hasAuthoritativeRawCompletionPayload(original, checkpoint)
      && hasSuccessfulToolResponse(original.tool_response, checkpoint, original)) {
      if (isTestOnlyPatchPayload(original)) {
        outcome = "active";
      } else if (checkpoint === "final_review" && isReviewPayload(original)) {
        outcome = reviewOutcomeFromResponse(original.tool_response);
      } else {
        outcome = "passed";
      }
    } else if (eventName === "PostToolUseFailure") {
      outcome = "failed";
    }
  }

  const terminalUnknown = Boolean(checkpoint && !outcome && eventName === "PostToolUse");

  return {
    ...result,
    ...(checkpoint && outcome ? { journey_checkpoint: checkpoint, journey_outcome: outcome } : {}),
    ...(checkpoint ? { journey_operation_key: journeyOperationKey(original) } : {}),
    ...(terminalUnknown ? { journey_terminal: true } : {}),
    ...(aggregate ? { journey_aggregate: aggregate } : {}),
  };
}

function codexPayload(payload) {
  let result;
  switch (payload.hook_event_name || "") {
    case "PreToolUse":
      result = { ...payload, permission_key: permissionKey(payload) };
      break;
    case "PostToolUseFailure":
    case "UserPromptSubmit":
    case "Stop":
    case "TaskCompleted":
    case "PreCompact":
    case "PostCompact":
    case "SubagentStart":
    case "SubagentStop":
      result = payload;
      break;
    case "PostToolUse":
      if (hasFailedToolResponse(payload.tool_response)) {
        const reviewFailure = isReviewPayload(payload);
        result = {
          ...payload,
          hook_event_name: "PostToolUseFailure",
          source_event: "PostToolUse",
          rollback_activity: !reviewFailure && payload.permission_mode !== "plan",
          review_failure: reviewFailure,
          permission_key: permissionKey(payload),
        };
        break;
      }
      result = hasSuccessfulToolResponse(payload.tool_response, "final_review") && isReviewPayload(payload) && isDirectForegroundReviewPayload(payload)
        ? { ...payload, hook_event_name: "TaskCompleted", source_event: "PostToolUse", permission_key: permissionKey(payload) }
        : { ...payload, permission_key: permissionKey(payload) };
      break;
    case "SessionStart":
      result = {
        hook_event_name: "Stop",
        session_id: payload.session_id || "",
        source_event: "SessionStart",
        start_source: payload.source || payload.start_source || "",
      };
      break;
    case "PermissionRequest":
      result = {
        hook_event_name: "Notification",
        notification_type: "permission_prompt",
        message: getPath(payload, "tool_input.description") || "Codex is requesting permission",
        session_id: payload.session_id || "",
        turn_id: payload.turn_id || "",
        tool_name: payload.tool_name || "",
        tool_input: payload.tool_input || {},
        permission_key: permissionKey(payload),
      };
      break;
    default:
      return null;
  }
  return withJourneySignal(result, payload);
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
    contextSpritePath,
    contextColor,
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
      context_sprite_path: normalizeWindowsPath(contextSpritePath || ""),
      context_color: contextColor || "",
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
    case "fit-title":
      line(firstFittingText(process.argv[3], process.argv.slice(4)));
      break;
    case "journey-profile":
      compact(journeyProfile(process.argv[3] || "codex-default"));
      break;
    case "journey-transition":
      compact(journeyTransition(
        process.argv[3] || "codex-default",
        process.argv[4] || "",
        process.argv[5] || "",
        process.argv[6] || "started",
        process.argv[7] || 0,
      ));
      break;
    case "journey-payload":
      compact(journeyPayload(
        process.argv[3] || "codex-default",
        process.argv[4] || "",
        process.argv[5] || "started",
      ));
      break;
    case "journey-render": {
      const theme = readJsonFile(process.argv[3]);
      compact(journeyRender(theme, process.argv[4] || "codex-default", process.argv[5] || ""));
      break;
    }
    case "journey-apply": {
      const payload = parseJson(readStdin(), {});
      compact(journeyApply(
        process.argv[3] || "codex-default",
        process.argv[4],
        process.argv[5],
        process.argv[6],
        process.argv[7],
        payload,
      ));
      break;
    }
    case "journey-complete-read-only":
      compact(journeyCompleteReadOnly(
        process.argv[3] || "codex-default",
        process.argv[4],
        process.argv[5],
        process.argv[6],
      ));
      break;
    case "journey-render-file":
      compact(journeyRender(
        readJsonFile(process.argv[3]),
        process.argv[4] || "codex-default",
        readJsonFile(process.argv[5]).current,
      ));
      break;
    case "journey-legend": {
      const theme = readJsonFile(process.argv[3]);
      line(journeyLegend(theme, process.argv[4] || "codex-default"));
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
      line([
        color[0] ?? "",
        color[1] ?? "",
        color[2] ?? "",
        state.sprite || "",
        state.badge || "",
        state.name || "",
        state.stage ?? "",
        state.progress_bar || "",
        state.journey_total ?? "",
      ].join("\x1f"));
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
      const color = Array.isArray(alert.color)
        ? `#${alert.color.map((channel) => Number(channel).toString(16).padStart(2, "0")).join("")}`
        : "";
      line([
        alert.level || "",
        alert.percent ?? "",
        alert.badge || "",
        alert.name || "",
        alert.sprite || "",
        color,
      ].join("\x1f"));
      break;
    }
    case "merge-codex-hooks": {
      const file = process.argv[3];
      const existing = fs.existsSync(file) ? readJsonFile(file) : { hooks: {} };
      process.stdout.write(`${JSON.stringify(mergeCodexHooks(existing, process.argv[4] || ""), null, 2)}\n`);
      break;
    }
    case "codex-visualhud-registration": {
      const file = process.argv[3];
      const existing = file && fs.existsSync(file) ? readJsonFile(file) : { hooks: {} };
      compact(codexVisualHudRegistration(existing));
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
