#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const matrixPath = path.join(root, "docs", "compatibility-matrix.v1.json");

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function sorted(values) {
  return [...values].sort((left, right) => left.localeCompare(right));
}

function equalLists(left, right) {
  return JSON.stringify(sorted(left)) === JSON.stringify(sorted(right));
}

function registeredEvents(host) {
  const config = readJson(path.join(root, host.hook_config));
  const adapterName = path.basename(host.adapter);
  return Object.entries(config.hooks || {})
    .filter(([, registrations]) =>
      (registrations || []).some((registration) =>
        (registration.hooks || []).some(
          (hook) => typeof hook.command === "string" && hook.command.includes(adapterName),
        ),
      ),
    )
    .map(([event]) => event);
}

function sensitiveFixtureReason(value, key = "") {
  const normalizedKey = key
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .toLowerCase()
    .replaceAll("-", "_");
  if (
    /^(?:token|.*_token|secret|.*_secret|password|.*_password|authorization|.*_authorization|credentials?|.*_credentials?|api_key|.*_api_key|private_key|.*_private_key)$/.test(
      normalizedKey,
    )
  ) {
    return `credential field '${key}'`;
  }
  if (typeof value === "string") {
    if (/\/(?:Users|home)\/[^/]+(?:\/|$)|[A-Za-z]:\\Users\\[^\\]+(?:\\|$)/i.test(value)) {
      return "user home-directory path";
    }
    return "";
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const reason = sensitiveFixtureReason(item);
      if (reason) return reason;
    }
    return "";
  }
  if (value && typeof value === "object") {
    for (const [childKey, childValue] of Object.entries(value)) {
      const reason = sensitiveFixtureReason(childValue, childKey);
      if (reason) return reason;
    }
  }
  return "";
}

function validate() {
  const errors = [];
  const matrix = readJson(matrixPath);

  if (matrix.schema_version !== 1) {
    errors.push("schema_version must be 1");
  }
  if (matrix.contract !== "host-renderer-lifecycle") {
    errors.push("contract must be host-renderer-lifecycle");
  }

  const hostIds = new Set();
  for (const host of matrix.hosts || []) {
    if (!host.id || hostIds.has(host.id)) {
      errors.push(`host id is missing or duplicated: ${host.id || "<empty>"}`);
      continue;
    }
    hostIds.add(host.id);

    for (const field of ["adapter", "hook_config", "fixture"]) {
      const value = host[field];
      if (!value || !fs.existsSync(path.join(root, value))) {
        errors.push(`${host.id}.${field} does not exist: ${value || "<empty>"}`);
      }
    }
    if (host.coverage !== "fixture-tested") {
      errors.push(`${host.id}.coverage must be fixture-tested`);
    }

    if (host.hook_config && fs.existsSync(path.join(root, host.hook_config))) {
      const actualEvents = registeredEvents(host);
      if (!equalLists(actualEvents, host.registered_events || [])) {
        errors.push(
          `${host.id} registered_events differ from ${host.hook_config}: expected ${sorted(actualEvents).join(", ")}`,
        );
      }
    }

    if (!host.fixture || !fs.existsSync(path.join(root, host.fixture))) {
      continue;
    }
    const fixture = readJson(path.join(root, host.fixture));
    if (fixture.schema_version !== 1 || fixture.host !== host.id) {
      errors.push(`${host.id} fixture schema or host id is invalid`);
      continue;
    }

    const caseIds = new Set();
    const coveredEvents = new Set();
    for (const fixtureCase of fixture.cases || []) {
      if (!fixtureCase.id || caseIds.has(fixtureCase.id)) {
        errors.push(`${host.id} fixture case id is missing or duplicated: ${fixtureCase.id || "<empty>"}`);
      }
      caseIds.add(fixtureCase.id);
      coveredEvents.add(fixtureCase.registered_event);

      if (!(host.registered_events || []).includes(fixtureCase.registered_event)) {
        errors.push(`${host.id}/${fixtureCase.id} names an unregistered event`);
      }
      if (!fixtureCase.expected_event || !fixtureCase.payload?.hook_event_name) {
        errors.push(`${host.id}/${fixtureCase.id} lacks a raw or expected event`);
      }
      if (!fixtureCase.model || !fixtureCase.effort) {
        errors.push(`${host.id}/${fixtureCase.id} lacks model/effort classification`);
      }

      const sensitiveReason = sensitiveFixtureReason(fixtureCase.payload);
      if (sensitiveReason) {
        errors.push(`${host.id}/${fixtureCase.id} contains non-sanitized data: ${sensitiveReason}`);
      }
    }

    const missingEvents = (host.registered_events || []).filter((event) => !coveredEvents.has(event));
    if (missingEvents.length) {
      errors.push(`${host.id} fixtures do not cover: ${missingEvents.join(", ")}`);
    }
  }

  if (!equalLists((matrix.renderers || []).map((renderer) => renderer.id), ["iterm2", "wezterm", "windows"])) {
    errors.push("renderers must list iterm2, wezterm, and windows");
  }
  for (const renderer of matrix.renderers || []) {
    if (renderer.coverage !== "fixture-tested") {
      errors.push(`${renderer.id}.coverage must be fixture-tested`);
    }
  }

  const requiredStates = ["work", "plan", "approval", "failure", "review", "compaction", "subagent", "idle", "done"];
  if (!equalLists(matrix.lifecycle_states || [], requiredStates)) {
    errors.push(`lifecycle_states must list ${requiredStates.join(", ")}`);
  }
  const lifecycleTitles = {
    work: "WORKING",
    plan: "Planning",
    approval: "Approval required",
    failure: "Error",
    review: "Reviewing",
    compaction: "Compacting",
    subagent: "Subagent",
    idle: "Your turn",
    done: "Complete",
  };
  const renderedTitles = new Set();
  for (const host of matrix.hosts || []) {
    if (!host.fixture || !fs.existsSync(path.join(root, host.fixture))) {
      continue;
    }
    const fixture = readJson(path.join(root, host.fixture));
    for (const fixtureCase of fixture.cases || []) {
      if (fixtureCase.render?.title) {
        renderedTitles.add(fixtureCase.render.title);
      }
    }
  }
  for (const state of requiredStates) {
    if (!renderedTitles.has(lifecycleTitles[state])) {
      errors.push(`${state} lacks a semantic renderer fixture (${lifecycleTitles[state]})`);
    }
  }

  for (const effort of ["medium", "high"]) {
    const lane = (matrix.model_lanes || []).find(
      (candidate) =>
        candidate.host === "codex" &&
        candidate.model === "gpt-5.6-sol" &&
        candidate.effort === effort,
    );
    if (!lane || lane.coverage !== "supervised" || lane.issue !== 16) {
      errors.push(`Codex gpt-5.6-sol/${effort} must remain supervised under issue #16`);
    }
  }

  const ci = matrix.policy?.default_ci || {};
  if (ci.network_credentials !== false || ci.paid_authenticated_tests !== false || ci.real_terminal_mutation !== false) {
    errors.push("default_ci must forbid credentials, paid tests, and real terminal mutation");
  }
  const canary = matrix.policy?.live_canary || {};
  if (
    canary.coverage !== "supervised" ||
    canary.issue !== 16 ||
    canary.timeout_required !== true ||
    canary.cost_boundary_required !== true ||
    canary.cleanup_required !== true
  ) {
    errors.push("live_canary must retain supervised timeout, cost, and cleanup boundaries under issue #16");
  }

  if (errors.length) {
    for (const error of errors) {
      process.stderr.write(`compatibility matrix: ${error}\n`);
    }
    process.exit(1);
  }

  const caseCount = (matrix.hosts || []).reduce((total, host) => {
    const fixture = readJson(path.join(root, host.fixture));
    return total + fixture.cases.length;
  }, 0);
  process.stdout.write(
    `Validated compatibility matrix v${matrix.schema_version}: ${matrix.hosts.length} hosts, ${matrix.renderers.length} renderers, ${caseCount} sanitized fixtures.\n`,
  );
}

function report() {
  const matrix = readJson(matrixPath);
  const lines = [`VisualHUD compatibility matrix v${matrix.schema_version}`, "", "Hosts:"];

  for (const host of matrix.hosts) {
    const fixture = readJson(path.join(root, host.fixture));
    lines.push(`- ${host.name} (host): ${host.coverage}, ${fixture.cases.length} sanitized payload cases`);
  }

  lines.push("", "Renderers:");
  for (const renderer of matrix.renderers) {
    const limitation = renderer.limitations.length ? `; ${renderer.limitations.join("; ")}` : "";
    lines.push(`- ${renderer.name}: ${renderer.coverage}${limitation}`);
  }

  lines.push("", "Model lanes:");
  for (const lane of matrix.model_lanes) {
    lines.push(`- ${lane.model} / ${lane.effort}: ${lane.coverage} (#${lane.issue})`);
  }

  lines.push(
    "",
    "Policy:",
    `- paid/authenticated tests in default CI: ${matrix.policy.default_ci.paid_authenticated_tests ? "yes" : "no"}`,
    `- real developer-pane mutation in default CI: ${matrix.policy.default_ci.real_terminal_mutation ? "yes" : "no"}`,
    `- live canary timeout/cost/cleanup: required under #${matrix.policy.live_canary.issue}`,
  );
  process.stdout.write(`${lines.join("\n")}\n`);
}

function sanitizeCheck() {
  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(0, "utf8"));
  } catch (error) {
    process.stderr.write(`sanitize-check: invalid JSON: ${error.message}\n`);
    process.exit(2);
  }
  const reason = sensitiveFixtureReason(payload);
  if (reason) {
    process.stderr.write(`sanitize-check: rejected ${reason}\n`);
    process.exit(1);
  }
}

const command = process.argv[2] || "report";
if (command === "validate") {
  validate();
} else if (command === "report") {
  report();
} else if (command === "sanitize-check") {
  sanitizeCheck();
} else {
  process.stderr.write("Usage: visualhud-compatibility.js [validate|report|sanitize-check]\n");
  process.exit(2);
}
