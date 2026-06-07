import { EventEmitter } from "node:events";
import { createRequire } from "node:module";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const require = createRequire(import.meta.url);

const adapterPath = join(root, "codex-integration", "appshot-codex-host-bridge", "codex-host-adapter.cjs");
const readmePath = join(root, "codex-integration", "appshot-codex-host-bridge", "README.md");
const evidenceRoot = resolve(root, "..", "codex-522", "mac-app");
const eventsPath = join(evidenceRoot, "artifacts", "comment-preload-runtime-events-522.txt");
const snippetsPath = join(evidenceRoot, "appshots-evidence", "522-appshots-snippets.js");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

for (const file of [adapterPath, readmePath, eventsPath, snippetsPath]) {
  assert(existsSync(file), `missing required file: ${file}`);
}

const adapterSource = readFileSync(adapterPath, "utf8");
const readme = readFileSync(readmePath, "utf8");
const events = readFileSync(eventsPath, "utf8");
const snippets = readFileSync(snippetsPath, "utf8");

for (const [name, text] of [
  ["codex-host-adapter.cjs", adapterSource],
  ["README.md", readme],
  ["522-appshots-snippets.js", snippets]
]) {
  for (const needle of [
    "sendMessageToHost",
    "subscribeToHostMessages",
    "codex_desktop:browser-sidebar-runtime-message"
  ]) {
    assert(text.includes(needle), `${name} missing ${needle}`);
  }
}

for (const eventName of [
  "browser-sidebar-runtime-message",
  "browser-sidebar-runtime-sync"
]) {
  assert(events.includes(eventName), `comment-preload-runtime-events-522.txt missing ${eventName}`);
}

for (const needle of [
  "host-managed browser state",
  "host-managed-browser-state",
  "browser-sidebar-runtime-sync",
  "browser-sidebar-runtime-message"
]) {
  assert(
    adapterSource.includes(needle) || readme.includes(needle) || events.includes(needle) || snippets.includes(needle),
    `missing Codex host integration anchor: ${needle}`
  );
}

const adapter = require(adapterPath);
assert(typeof adapter.installAppShotCodexHostBridge === "function", "missing installAppShotCodexHostBridge");
assert(adapter.hostOwner === "codex-electron-host", "host owner drifted");
assert(adapter.hostTransport === "codex-electron-ipc+appshot-electron-ipc", "host transport drifted");
assert(adapter.hostChannel === "codex_desktop:browser-sidebar-runtime-message", "host channel drifted");
assert(JSON.stringify(adapter.hostAPI) === JSON.stringify(["sendMessageToHost", "subscribeToHostMessages"]), "host API drifted");

const ipcMain = new EventEmitter();
ipcMain.on = ipcMain.on.bind(ipcMain);
ipcMain.removeListener = ipcMain.removeListener.bind(ipcMain);

let observed = null;
const bridge = adapter.installAppShotCodexHostBridge(ipcMain, {
  getBrowserState(seed) {
    return Object.assign({
      annotationEditorMode: "comment",
      isOriginalViewEnabled: true
    }, seed);
  },
  onCodexRuntimeMessage(payload, event, state) {
    observed = { payload, event, state };
  }
});

assert(bridge.hostOwner === "codex-electron-host", "installed bridge owner drifted");
assert(bridge.getState().privateCodexWebviewHostAttached === true, "installed adapter should report private host attached inside host");
assert(bridge.getState().hostManagedBrowserStateAvailable === true, "installed adapter lost browser state hook");

let echoed = null;
const sender = {
  send(channel, payload) {
    echoed = { channel, payload };
  },
  isDestroyed() {
    return false;
  }
};

ipcMain.emit("codex_desktop:browser-sidebar-runtime-message", { sender }, {
  requestId: "codex-fixture",
  message: { type: "ping" },
  event: {
    type: "browser-sidebar-runtime-message",
    message: { type: "ping" }
  }
});

assert(observed?.payload?.requestId === "codex-fixture", "adapter did not observe runtime message");
assert(bridge.getState().eventCount === 1, "adapter did not log runtime message");
assert(echoed?.channel === "codex_desktop:browser-sidebar-runtime-message", "underlying Electron bridge did not echo channel");

let sent = null;
const webContents = {
  send(channel, payload) {
    sent = { channel, payload };
  },
  isDestroyed() {
    return false;
  }
};
const sentOK = bridge.sendCodexHostState(webContents, {
  interactionMode: "design",
  isDesignModifierPressed: true
});

assert(sentOK === true, "sendCodexHostState should return true for live webContents");
assert(sent?.channel === "codex_desktop:browser-sidebar-runtime-message", "host state used wrong channel");
assert(sent?.payload?.hostOwner === "codex-electron-host", "host state lost Codex host owner");
assert(sent?.payload?.hostTransport === "codex-electron-ipc+appshot-electron-ipc", "host state lost Codex host transport");
assert(sent?.payload?.state?.type === "browser-sidebar-runtime-sync", "host state did not send runtime sync");
assert(sent?.payload?.state?.isOriginalViewEnabled === true, "host state did not use getBrowserState hook");
assert(bridge.getState().eventCount === 2, "host state sync was not logged");

bridge.dispose();

console.log("codex host integration: ok");
