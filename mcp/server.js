#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const appshot = resolveAppShotBinary();

function resolveAppShotBinary() {
  if (process.env.APPSHOT_BIN) return process.env.APPSHOT_BIN;

  const which = spawnSync("/usr/bin/env", ["sh", "-lc", "command -v appshot"], {
    encoding: "utf8"
  });
  const fromPath = which.stdout?.trim();
  if (fromPath) return fromPath;

  if (process.env.HOME) {
    const installed = resolve(process.env.HOME, ".local", "bin", "appshot");
    if (existsSync(installed)) return installed;
  }
  return resolve(root, ".build", "debug", "appshot");
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  for (;;) {
    const newline = buffer.indexOf("\n");
    if (newline < 0) break;
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (line.length > 0) handleLine(line);
  }
});

// @sm:node mcp.appshot.capture
// @sm:feature appshot.capture
// @sm:prev codex.mcp-client
// @sm:next appshot.cli
// @sm:deps jsonrpc-2.0,appshot-cli
// @sm:evidence node mcp/server.js plus MCP tools/list request
function handleLine(line) {
  let request;
  try {
    request = JSON.parse(line);
  } catch (error) {
    respond(null, null, { code: -32700, message: String(error) });
    return;
  }

  const { id, method, params } = request;
  try {
    if (method === "initialize") {
      respond(id, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "appshot", version: "0.1.15" }
      });
    } else if (method === "tools/list") {
      respond(id, { tools: tools() });
    } else if (method === "tools/call") {
      respond(id, callTool(params));
    } else if (method === "notifications/initialized") {
      // No response for notifications.
    } else {
      respond(id, null, { code: -32601, message: `Unknown method: ${method}` });
    }
  } catch (error) {
    respond(id, null, { code: -32000, message: String(error?.message || error) });
  }
}

function tools() {
  return [
    {
      name: "appshot_capture",
      description: "Capture the frontmost macOS app as JSON or Codex-style appshot text with app/window metadata, accessibility text tree, Codex browser-comment payload adapter, optional screenshot, and optional OCR fallback. By default, uses a recent AppShot.app left+right Option shortcut cache when available.",
      inputSchema: {
        type: "object",
        properties: {
          includeScreenshot: { type: "boolean", default: false },
          browserAnnotationScreenshotsMode: { type: "string", enum: ["always", "necessary"], default: "necessary" },
          browserInteractionMode: { type: "string", default: "comment" },
          browserAnnotationEditorMode: { type: "string", enum: ["comment", "design"], default: "comment" },
          browserAgentControlling: { type: "boolean", default: false },
          browserCanUseTweaks: { type: "boolean", default: true },
          browserDesignModifierPressed: { type: "boolean", default: false },
          browserOriginalViewEnabled: { type: "boolean", default: false },
          browserTweaksEditorOpen: { type: "boolean", default: false },
          browserViewportScale: { type: "number", default: 1 },
          browserZoomPercent: { type: "number" },
          browserActiveDesignChange: { type: "object" },
          includeBrowserDOM: { type: "boolean", default: false },
          browserDOMTimeout: { type: "number", default: 1.5 },
          browserDOMFixture: { type: "object" },
          browserDOMInstallBridge: { type: "boolean", default: false },
          browserDOMClearBridgeLog: { type: "boolean", default: false },
          includeElectronDebugging: { type: "boolean", default: false },
          electronDebuggingTimeout: { type: "number", default: 2 },
          includeOCR: { type: "boolean", default: false },
          screenshotPath: { type: "string" },
          windowID: { type: "number" },
          windowTitle: { type: "string" },
          pid: { type: "number" },
          bundleID: { type: "string" },
          activateTarget: { type: "boolean", default: true },
          requestAppCapture: { type: "boolean", default: false },
          appCaptureTimeout: { type: "number", default: 2 },
          format: { type: "string", enum: ["json", "codex"], default: "json" },
          maxDepth: { type: "number", default: 60 },
          maxChildren: { type: "number", default: 240 },
          maxOCRObservations: { type: "number", default: 240 },
          accessibilityTimeout: { type: "number", default: 20 },
          screenshotTimeout: { type: "number", default: 3 },
          useRecentCache: { type: "boolean", default: true },
          preferRecentCache: { type: "boolean", default: true },
          cacheMaxAge: { type: "number", default: 15 },
          writeCache: { type: "boolean", default: false },
          cacheTrigger: { type: "string" }
        }
      }
    },
    {
      name: "appshot_permissions",
      description: "Check macOS Accessibility and Screen Recording permissions, including the current TCC identity and stable grant target guidance.",
      inputSchema: {
        type: "object",
        properties: {
          prompt: { type: "boolean", default: false }
        }
      }
    },
    {
      name: "appshot_status",
      description: "Return complete AppShot readiness state, including permissions, permission identity stability, front app, primary window, and blockers.",
      inputSchema: {
        type: "object",
        properties: {
          prompt: { type: "boolean", default: false }
        }
      }
    },
    {
      name: "appshot_codex_apps_status",
      description: "Return AppShot's Codex accessible-connector readiness status, including codexAppsReady, tool surface, permission blockers, and force-refetch guidance.",
      inputSchema: {
        type: "object",
        properties: {
          prompt: { type: "boolean", default: false }
        }
      }
    },
    {
      name: "appshot_codex_computer_use_status",
      description: "Report Codex Computer Use parity diagnostics, including CUA service discovery, app approvals, and host native-pipe bridge requirements.",
      inputSchema: { type: "object", properties: {} }
    },
    {
      name: "appshot_list_windows",
      description: "List regular running apps, CG windows, and macOS Accessibility windows, including exact capture parameters and AX-only windowTitle targets for follow-up appshot_capture calls.",
      inputSchema: { type: "object", properties: {} }
    },
    {
      name: "list_apps",
      description: "Computer Use-compatible alias: list running apps that AppShot can target.",
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
      annotations: {
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
        readOnlyHint: true
      }
    },
    {
      name: "get_app_state",
      description: "Computer Use-compatible alias: get the state of an app's key window and return a screenshot plus Codex-style accessibility tree.",
      inputSchema: {
        type: "object",
        properties: {
          app: { type: "string", description: "App name, full app path, or unambiguous bundle identifier" },
          windowTitle: { type: "string", description: "Optional macOS Accessibility window title to target inside the app" }
        },
        required: ["app"],
        additionalProperties: false
      },
      annotations: {
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
        readOnlyHint: true
      }
    }
  ];
}

function callTool(params = {}) {
  const name = params.name;
  const args = params.arguments || {};
  if (name === "list_apps") return callComputerUseListApps();
  if (name === "get_app_state") return callComputerUseGetAppState(args);

  const cliArgs = [];

  if (name === "appshot_capture") {
    cliArgs.push("capture", "--pretty");
    if (args.includeScreenshot) cliArgs.push("--include-screenshot");
    if (args.browserAnnotationScreenshotsMode) cliArgs.push("--browser-annotation-screenshots-mode", String(args.browserAnnotationScreenshotsMode));
    if (args.browserInteractionMode) cliArgs.push("--browser-interaction-mode", String(args.browserInteractionMode));
    if (args.browserAnnotationEditorMode) cliArgs.push("--browser-annotation-editor-mode", String(args.browserAnnotationEditorMode));
    if (args.browserAgentControlling) cliArgs.push("--browser-agent-controlling");
    if (args.browserCanUseTweaks === false) cliArgs.push("--browser-disable-tweaks");
    if (args.browserDesignModifierPressed) cliArgs.push("--browser-design-modifier-pressed");
    if (args.browserOriginalViewEnabled) cliArgs.push("--browser-original-view-enabled");
    if (args.browserTweaksEditorOpen) cliArgs.push("--browser-tweaks-editor-open");
    if (args.browserViewportScale != null) cliArgs.push("--browser-viewport-scale", String(args.browserViewportScale));
    if (args.browserZoomPercent != null) cliArgs.push("--browser-zoom-percent", String(args.browserZoomPercent));
    if (args.browserActiveDesignChange != null) cliArgs.push("--browser-active-design-change-json", JSON.stringify(args.browserActiveDesignChange));
    if (args.includeBrowserDOM) cliArgs.push("--include-browser-dom");
    if (args.browserDOMTimeout != null) cliArgs.push("--browser-dom-timeout", String(args.browserDOMTimeout));
    if (args.browserDOMFixture != null) cliArgs.push("--browser-dom-fixture-json", JSON.stringify(args.browserDOMFixture));
    if (args.browserDOMInstallBridge) cliArgs.push("--browser-dom-install-bridge");
    if (args.browserDOMClearBridgeLog) cliArgs.push("--browser-dom-clear-bridge-log");
    if (args.includeElectronDebugging) cliArgs.push("--include-electron-debugging");
    if (args.electronDebuggingTimeout != null) cliArgs.push("--electron-debugging-timeout", String(args.electronDebuggingTimeout));
    if (args.includeOCR) cliArgs.push("--include-ocr");
    if (args.screenshotPath) cliArgs.push("--screenshot", String(args.screenshotPath));
    if (args.windowID != null) cliArgs.push("--window-id", String(args.windowID));
    if (args.windowTitle) cliArgs.push("--window-title", String(args.windowTitle));
    if (args.pid != null) cliArgs.push("--pid", String(args.pid));
    if (args.bundleID) cliArgs.push("--bundle-id", String(args.bundleID));
    if (args.activateTarget === false) cliArgs.push("--no-activate-target");
    if (args.requestAppCapture) cliArgs.push("--request-app-capture");
    if (args.appCaptureTimeout != null) cliArgs.push("--app-capture-timeout", String(args.appCaptureTimeout));
    if (args.useRecentCache === false || args.preferRecentCache === false) cliArgs.push("--no-cache");
    if (args.cacheMaxAge != null) cliArgs.push("--cache-max-age", String(args.cacheMaxAge));
    if (args.writeCache) cliArgs.push("--write-cache");
    if (args.cacheTrigger) cliArgs.push("--cache-trigger", String(args.cacheTrigger));
    if (args.format === "codex") cliArgs.push("--format", "codex");
    cliArgs.push("--max-depth", String(args.maxDepth ?? 60));
    cliArgs.push("--max-children", String(args.maxChildren ?? 240));
    if (args.maxOCRObservations != null) cliArgs.push("--max-ocr-observations", String(args.maxOCRObservations));
    cliArgs.push("--accessibility-timeout", String(args.accessibilityTimeout ?? 20));
    if (args.screenshotTimeout != null) cliArgs.push("--screenshot-timeout", String(args.screenshotTimeout));
  } else if (name === "appshot_permissions") {
    cliArgs.push("permissions", "--pretty");
    if (args.prompt) cliArgs.push("--prompt");
  } else if (name === "appshot_status") {
    cliArgs.push("status", "--pretty");
    if (args.prompt) cliArgs.push("--prompt");
  } else if (name === "appshot_codex_apps_status") {
    cliArgs.push("codex-apps-status", "--pretty");
    if (args.prompt) cliArgs.push("--prompt");
  } else if (name === "appshot_codex_computer_use_status") {
    cliArgs.push("codex-computer-use-status", "--pretty");
  } else if (name === "appshot_list_windows") {
    cliArgs.push("list-windows", "--pretty");
  } else {
    throw new Error(`Unknown tool: ${name}`);
  }

  return {
    content: [{ type: "text", text: runAppShot(cliArgs).trim() }]
  };
}

function runAppShot(cliArgs) {
  const result = spawnSync(appshot, cliArgs, {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(result.stderr || `appshot exited with status ${result.status}`);
  }
  return result.stdout;
}

function runAppShotJSON(cliArgs) {
  const stdout = runAppShot(cliArgs);
  return JSON.parse(stdout);
}

function callComputerUseListApps() {
  const payload = runAppShotJSON(["list-windows", "--pretty"]);
  const apps = Array.isArray(payload.applications) ? payload.applications : [];
  const lines = apps.map((app) => {
    const name = app.localizedName || app.name || app.bundleIdentifier || "Unknown";
    const path = app.bundleURL || app.bundlePath || "";
    const bundleID = app.bundleIdentifier || "";
    const windows = Array.isArray(app.windows) ? app.windows.length : 0;
    const axWindows = Array.isArray(app.accessibilityWindows) ? app.accessibilityWindows.length : 0;
    return `${name} — ${path} — ${bundleID} [running, windows=${windows}, accessibilityWindows=${axWindows}]`;
  });
  return {
    content: [{ type: "text", text: lines.join("\n") }]
  };
}

function callComputerUseGetAppState(args) {
  const app = String(args.app || "").trim();
  if (!app) {
    return {
      isError: true,
      content: [{ type: "text", text: "Missing required argument: app" }]
    };
  }

  const target = resolveComputerUseAppTarget(app);
  if (!target) {
    return {
      isError: true,
      content: [{ type: "text", text: `Invalid app: ${app}` }]
    };
  }

  const dir = mkdtempSync(join(tmpdir(), "appshot-get-app-state-"));
  const screenshotPath = join(dir, "screenshot.png");
  const cliArgs = [
    "capture",
    "--pretty",
    "--format",
    "json",
    "--include-screenshot",
    "--screenshot",
    screenshotPath,
    "--no-cache",
    "--max-depth",
    "60",
    "--max-children",
    "240",
    "--accessibility-timeout",
    "20"
  ];
  if (target.bundleID) cliArgs.push("--bundle-id", target.bundleID);
  else if (target.pid != null) cliArgs.push("--pid", String(target.pid));
  if (args.windowTitle) cliArgs.push("--window-title", String(args.windowTitle));

  const payload = runAppShotJSON(cliArgs);
  const codex = payload.codex || {};
  const text = codex.text || JSON.stringify(payload, null, 2);
  const content = [{ type: "text", text }];
  if (existsSync(screenshotPath)) {
    content.push({
      type: "image",
      data: readFileSync(screenshotPath).toString("base64"),
      mimeType: "image/png"
    });
  }
  return {
    _meta: {
      source: "appshot-get-app-state",
      app,
      windowTitle: args.windowTitle || "",
      target,
      screenshotPath,
      codexComputerUseStatus: payload.codexComputerUseStatus || null
    },
    content
  };
}

function resolveComputerUseAppTarget(app) {
  const payload = runAppShotJSON(["list-windows", "--pretty"]);
  const apps = Array.isArray(payload.applications) ? payload.applications : [];
  const wanted = normalizeAppToken(app);
  const match = apps.find((candidate) => {
    const names = [
      candidate.localizedName,
      candidate.name,
      candidate.bundleIdentifier,
      candidate.bundleURL,
      candidate.bundlePath
    ].filter(Boolean).map(normalizeAppToken);
    return names.includes(wanted);
  });
  if (match) {
    return {
      bundleID: match.bundleIdentifier || undefined,
      pid: match.captureParameters?.pid ?? match.processIdentifier,
      name: match.localizedName || match.name || "",
      path: match.bundleURL || match.bundlePath || ""
    };
  }
  if (!app.includes("/") && app.includes(".")) {
    return { bundleID: app };
  }
  return null;
}

function normalizeAppToken(value) {
  return String(value || "")
    .trim()
    .replace(/\/+$/, "")
    .toLowerCase();
}

function respond(id, result, error) {
  if (id == null) return;
  const message = error
    ? { jsonrpc: "2.0", id, error }
    : { jsonrpc: "2.0", id, result };
  process.stdout.write(`${JSON.stringify(message)}\n`);
}
