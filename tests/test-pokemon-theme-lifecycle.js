#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const rootDir = path.resolve(__dirname, "..");
const themesDir = process.env.VISUALHUD_TEST_THEMES_DIR || path.join(rootDir, "themes");
const themeFile = path.join(themesDir, "pokemon", "theme.json");
const spritesDir = path.join(themesDir, "pokemon", "sprites");
const engine = path.join(rootDir, "engine.sh");
const sessionId = "visualhud-pokemon-e2e";

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function assertPng(sprite) {
  const file = path.join(spritesDir, `${sprite}.png`);
  assert.ok(fs.existsSync(file), `missing sprite file: ${sprite}`);

  const header = Buffer.alloc(24);
  const fd = fs.openSync(file, "r");
  try {
    fs.readSync(fd, header, 0, header.length, 0);
  } finally {
    fs.closeSync(fd);
  }

  assert.deepStrictEqual(
    [...header.subarray(0, 8)],
    [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
    `invalid PNG header: ${sprite}`,
  );
  assert.ok(header.readUInt32BE(16) > 0, `invalid PNG width: ${sprite}`);
  assert.ok(header.readUInt32BE(20) > 0, `invalid PNG height: ${sprite}`);
}

function lifecycleEntries(theme) {
  const lifecycle = ["blocked", "review", "done", "idle", "error"].map((kind) => ({
    kind,
    name: theme[kind].name,
    sprite: theme[kind].sprite || "",
  }));
  const contexts = Object.entries(theme.context_alerts || {}).map(([level, state]) => ({
    kind: "context",
    level,
    name: state.name,
    sprite: state.sprite || "",
  }));
  return [...lifecycle, ...contexts];
}

function validateThemeContract(theme) {
  assert.strictEqual(theme.stages.length, 11, "Pokemon theme keeps the 11-stage progression");
  assert.strictEqual(theme.stages[9].sprite, "wartortle", "stage 10 stays Wartortle");
  assert.strictEqual(theme.stages[10].sprite, "blastoise", "stage 11 stays Blastoise");

  assert.strictEqual(theme.review.sprite, "alakazam", "review uses Alakazam");
  assert.strictEqual(theme.done.sprite, "mew", "done uses Mew");
  assert.strictEqual(theme.idle.sprite, "eevee", "idle uses Eevee");
  assert.strictEqual(theme.error.sprite, "psyduck", "error uses Psyduck");
  assert.strictEqual(theme.context_alerts.warning.sprite, "chansey", "warning context uses Chansey");
  assert.strictEqual(theme.context_alerts.critical.sprite, "blissey", "critical context uses Blissey");

  const stageSprites = new Set(theme.stages.flatMap((stage) => [stage.sprite, ...(stage.shade_sprites || [])]).filter(Boolean));
  const stateSprites = lifecycleEntries(theme).map((entry) => entry.sprite);
  const emptyStates = lifecycleEntries(theme).filter((entry) => !entry.sprite).map((entry) => `${entry.kind}:${entry.name}`);
  assert.deepStrictEqual(emptyStates, [], "lifecycle/context states must not render empty sprite cards");
  assert.strictEqual(new Set(stateSprites).size, stateSprites.length, "lifecycle/context sprites are unique");

  const stageReuse = lifecycleEntries(theme)
    .filter((entry) => entry.sprite && stageSprites.has(entry.sprite))
    .map((entry) => `${entry.kind}:${entry.name}:${entry.sprite}`);
  assert.deepStrictEqual(stageReuse, [], "lifecycle/context states must not duplicate progress sprites");

  const allSprites = new Set([...stageSprites, ...stateSprites]);
  for (const sprite of allSprites) {
    assertPng(sprite);
  }
}

function runEngine(payload, env) {
  const result = childProcess.spawnSync("bash", [engine], {
    cwd: rootDir,
    env,
    input: `${JSON.stringify(payload)}\n`,
    encoding: "utf8",
  });
  assert.strictEqual(result.status, 0, result.stderr || result.stdout);
}

function validateEngineLifecycle() {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "visualhud-pokemon-e2e."));
  const stageFile = path.join(stateDir, `claude-cooking-stage_${sessionId}`);
  const counterFile = path.join(stateDir, `claude-cooking-counter_${sessionId}`);
  const ttyLog = path.join(stateDir, "tty.log");
  const env = {
    ...process.env,
    ITERM_SESSION_ID: sessionId,
    VISUALHUD_THEME: "pokemon",
    VISUALHUD_THEMES_DIR: themesDir,
    VISUALHUD_STATE_DIR: stateDir,
    VISUALHUD_TTY: ttyLog,
    VISUALHUD_RENDERER: "windows",
    VISUALHUD_REAPPLY_DELAY: "0",
  };

  try {
    fs.writeFileSync(counterFile, "280");
    runEngine({ hook_event_name: "PreToolUse", tool_name: "Read", session_id: "test" }, env);
    assert.strictEqual(fs.readFileSync(stageFile, "utf8"), "wartortle", "count 281 uses Wartortle");

    fs.writeFileSync(counterFile, "400");
    runEngine({ hook_event_name: "PreToolUse", tool_name: "Read", session_id: "test" }, env);
    assert.strictEqual(fs.readFileSync(stageFile, "utf8"), "blastoise", "count 401 uses Blastoise");

    runEngine(
      {
        hook_event_name: "PreToolUse",
        tool_name: "Bash",
        tool_input: { command: 'codex exec -o .reviews/latest-review.md "Review before ship"' },
        session_id: "test",
      },
      env,
    );
    assert.strictEqual(fs.readFileSync(stageFile, "utf8"), "alakazam", "review uses Alakazam");

    runEngine({ hook_event_name: "TaskCompleted", task: "code review completed", session_id: "test" }, env);
    assert.strictEqual(fs.readFileSync(stageFile, "utf8"), "mew", "review completion uses Mew");

    runEngine({ hook_event_name: "Notification", notification_type: "idle_prompt", session_id: "test" }, env);
    assert.strictEqual(fs.readFileSync(stageFile, "utf8"), "eevee", "idle prompt uses Eevee");

    runEngine({ hook_event_name: "StopFailure", error: "rate_limit", session_id: "test" }, env);
    assert.strictEqual(fs.readFileSync(stageFile, "utf8"), "psyduck", "stop failure uses Psyduck");
  } finally {
    fs.rmSync(stateDir, { recursive: true, force: true });
  }
}

const theme = readJson(themeFile);
validateThemeContract(theme);
validateEngineLifecycle();

console.log("PASS: Pokemon theme lifecycle and engine states are complete and distinct");
