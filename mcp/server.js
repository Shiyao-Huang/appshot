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
        serverInfo: { name: "appshot", version: "0.1.2" }
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
      description: "Capture the frontmost macOS app as JSON or Codex-style appshot text with app/window metadata, accessibility text tree, optional screenshot, and optional OCR fallback.",
      inputSchema: {
        type: "object",
        properties: {
          includeScreenshot: { type: "boolean", default: false },
          includeOCR: { type: "boolean", default: false },
          screenshotPath: { type: "string" },
          windowID: { type: "number" },
          pid: { type: "number" },
          bundleID: { type: "string" },
          format: { type: "string", enum: ["json", "codex"], default: "json" },
          maxDepth: { type: "number", default: 10 },
          maxChildren: { type: "number", default: 120 },
          maxOCRObservations: { type: "number", default: 240 },
          accessibilityTimeout: { type: "number", default: 8 },
          screenshotTimeout: { type: "number", default: 3 }
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
    if (args.includeOCR) cliArgs.push("--include-ocr");
    if (args.screenshotPath) cliArgs.push("--screenshot", String(args.screenshotPath));
    if (args.windowID != null) cliArgs.push("--window-id", String(args.windowID));
    if (args.pid != null) cliArgs.push("--pid", String(args.pid));
    if (args.bundleID) cliArgs.push("--bundle-id", String(args.bundleID));
    if (args.format === "codex") cliArgs.push("--format", "codex");
    if (args.maxDepth != null) cliArgs.push("--max-depth", String(args.maxDepth));
    if (args.maxChildren != null) cliArgs.push("--max-children", String(args.maxChildren));
    if (args.maxOCRObservations != null) cliArgs.push("--max-ocr-observations", String(args.maxOCRObservations));
    if (args.accessibilityTimeout != null) cliArgs.push("--accessibility-timeout", String(args.accessibilityTimeout));
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
