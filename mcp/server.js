#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
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
        serverInfo: { name: "appshot", version: "0.1.10" }
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
          includeOCR: { type: "boolean", default: false },
          screenshotPath: { type: "string" },
          windowID: { type: "number" },
          pid: { type: "number" },
          bundleID: { type: "string" },
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
      name: "appshot_list_windows",
      description: "List regular running apps and visible windows, including exact capture parameters for follow-up appshot_capture calls.",
      inputSchema: { type: "object", properties: {} }
    }
  ];
}

function callTool(params = {}) {
  const name = params.name;
  const args = params.arguments || {};
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
    if (args.includeOCR) cliArgs.push("--include-ocr");
    if (args.screenshotPath) cliArgs.push("--screenshot", String(args.screenshotPath));
    if (args.windowID != null) cliArgs.push("--window-id", String(args.windowID));
    if (args.pid != null) cliArgs.push("--pid", String(args.pid));
    if (args.bundleID) cliArgs.push("--bundle-id", String(args.bundleID));
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
  } else if (name === "appshot_list_windows") {
    cliArgs.push("list-windows", "--pretty");
  } else {
    throw new Error(`Unknown tool: ${name}`);
  }

  const result = spawnSync(appshot, cliArgs, { encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(result.stderr || `appshot exited with status ${result.status}`);
  }
  return {
    content: [{ type: "text", text: result.stdout.trim() }]
  };
}

function respond(id, result, error) {
  if (id == null) return;
  const message = error
    ? { jsonrpc: "2.0", id, error }
    : { jsonrpc: "2.0", id, result };
  process.stdout.write(`${JSON.stringify(message)}\n`);
}
