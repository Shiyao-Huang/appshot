import { EventEmitter } from "node:events";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const require = createRequire(import.meta.url);

const adapterPath = join(root, "codex-integration", "appshot-codex-host-bridge", "codex-host-adapter.cjs");
const readmePath = join(root, "codex-integration", "appshot-codex-host-bridge", "README.md");
const injectionAnalyzerPath = join(root, "scripts", "analyze_codex_electron_host_injection.mjs");
const patcherPath = join(root, "scripts", "patch_codex_electron_host_for_appshot.mjs");
const evidenceRoot = resolve(root, "..", "codex-522", "mac-app");
const eventsPath = join(evidenceRoot, "artifacts", "comment-preload-runtime-events-522.txt");
const snippetsPath = join(evidenceRoot, "appshots-evidence", "522-appshots-snippets.js");
const mainBundlePath = join(evidenceRoot, "asar-522", ".vite", "build", "main-DVEWN1ng.js");
const commentPreloadPath = join(evidenceRoot, "asar-522", ".vite", "build", "comment-preload.js");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

for (const file of [
  adapterPath,
  readmePath,
  injectionAnalyzerPath,
  patcherPath,
  eventsPath,
  snippetsPath,
  mainBundlePath,
  commentPreloadPath
]) {
  assert(existsSync(file), `missing required file: ${file}`);
}

const adapterSource = readFileSync(adapterPath, "utf8");
const readme = readFileSync(readmePath, "utf8");
const injectionAnalyzer = readFileSync(injectionAnalyzerPath, "utf8");
const patcher = readFileSync(patcherPath, "utf8");
const events = readFileSync(eventsPath, "utf8");
const snippets = readFileSync(snippetsPath, "utf8");
const mainBundle = readFileSync(mainBundlePath, "utf8");
const commentPreload = readFileSync(commentPreloadPath, "utf8");

for (const [name, text] of [
  ["codex-host-adapter.cjs", adapterSource],
  ["README.md", readme],
  ["analyze_codex_electron_host_injection.mjs", injectionAnalyzer],
  ["patch_codex_electron_host_for_appshot.mjs", patcher],
  ["522-appshots-snippets.js", snippets],
  ["comment-preload.js", commentPreload]
]) {
  for (const needle of [
    "sendMessageToHost",
    "subscribeToHostMessages",
    "codex_desktop:browser-sidebar-runtime-message"
  ]) {
    assert(text.includes(needle), `${name} missing ${needle}`);
  }
}

for (const [name, text] of [
  ["codex-host-adapter.cjs", adapterSource],
  ["README.md", readme],
  ["analyze_codex_electron_host_injection.mjs", injectionAnalyzer],
  ["patch_codex_electron_host_for_appshot.mjs", patcher],
  ["522-appshots-snippets.js", snippets],
  ["main-DVEWN1ng.js", mainBundle],
  ["comment-preload.js", commentPreload]
]) {
  for (const needle of [
    "codex_desktop:browser-sidebar-runtime-message",
    "codex_desktop:message-for-view"
  ]) {
    assert(text.includes(needle), `${name} missing ${needle}`);
  }
}

const mainPreload = readFileSync(join(evidenceRoot, "asar-522", ".vite", "build", "preload.js"), "utf8");
assert(mainPreload.includes("codex_desktop:message-from-view"), "preload.js missing main view inbound channel");
assert(mainPreload.includes("codex_desktop:message-for-view"), "preload.js missing main view outbound channel");

for (const eventName of [
  "browser-sidebar-runtime-message",
  "browser-sidebar-runtime-sync"
]) {
  assert(events.includes(eventName), `comment-preload-runtime-events-522.txt missing ${eventName}`);
}

for (const needle of [
  "host-managed browser state",
  "host-managed-browser-state",
  "ipcRenderer.invoke/ipcMain.handle",
  "webContents.send/ipcRenderer.on",
  "patch_codex_electron_host_for_appshot",
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
assert(adapter.hostInboundChannel === "codex_desktop:browser-sidebar-runtime-message", "host inbound channel drifted");
assert(adapter.hostOutboundChannel === "codex_desktop:message-for-view", "host outbound channel drifted");
assert(adapter.hostToViewChannel === "codex_desktop:message-for-view", "host-to-view channel drifted");
assert(adapter.ipcPattern === "ipcRenderer.invoke/ipcMain.handle + webContents.send/ipcRenderer.on", "Codex IPC pattern drifted");
assert(JSON.stringify(adapter.hostAPI) === JSON.stringify(["sendMessageToHost", "subscribeToHostMessages"]), "host API drifted");

const ipcMain = new EventEmitter();
ipcMain.on = ipcMain.on.bind(ipcMain);
ipcMain.removeListener = ipcMain.removeListener.bind(ipcMain);
const handleMap = new Map();
const originalHandle = function handle(channel, handler) {
  handleMap.set(channel, handler);
};
ipcMain.handle = originalHandle;

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
assert(bridge.getState().ipcMainHandleTapInstalled === true, "installed adapter did not tap ipcMain.handle");
assert(ipcMain.handle !== originalHandle, "installed adapter did not patch ipcMain.handle");

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

let handledPayload = null;
ipcMain.handle("codex_desktop:browser-sidebar-runtime-message", async (_event, payload) => {
  handledPayload = payload;
  return { ok: true, type: payload.type };
});
assert(bridge.getState().codexRuntimeHandlerWrapped === true, "adapter did not wrap Codex ipcMain.handle registration");
const codexRuntimeHandler = handleMap.get("codex_desktop:browser-sidebar-runtime-message");
assert(typeof codexRuntimeHandler === "function", "Codex runtime handler was not registered");
const invokeResult = await codexRuntimeHandler({
  sender: {
    id: 42
  }
}, {
  type: "browser-sidebar-runtime-image-drag-started",
  sourceUrl: "https://example.test/image.png"
});
assert(invokeResult?.ok === true, "wrapped Codex runtime handler did not return original result");
assert(handledPayload?.type === "browser-sidebar-runtime-image-drag-started", "wrapped handler did not call original handler");
assert(bridge.getState().eventCount === 2, "adapter did not observe Codex invoke/handle runtime message");
assert(bridge.getState().lastRuntimeMessageType === "browser-sidebar-runtime-image-drag-started", "adapter did not preserve Codex runtime event type");

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
assert(sent?.channel === "codex_desktop:message-for-view", "host state used wrong host-to-view channel");
assert(sent?.payload?.hostOwner === "codex-electron-host", "host state lost Codex host owner");
assert(sent?.payload?.hostTransport === "codex-electron-ipc+appshot-electron-ipc", "host state lost Codex host transport");
assert(sent?.payload?.type === "browser-sidebar-runtime-sync", "host state did not send runtime sync");
assert(sent?.payload?.isOriginalViewEnabled === true, "host state did not use getBrowserState hook");
assert(bridge.getState().eventCount === 3, "host state sync was not logged");

const eventSentOK = bridge.sendCodexRuntimeEvent(webContents, {
  type: "browser-sidebar-runtime-create-comment-at-point",
  point: { x: 10, y: 20 }
});
assert(eventSentOK === true, "sendCodexRuntimeEvent should return true for live webContents");
assert(sent?.channel === "codex_desktop:message-for-view", "runtime event used wrong host-to-view channel");
assert(sent?.payload?.type === "browser-sidebar-runtime-create-comment-at-point", "runtime event payload drifted");

const analyzer = spawnSync(process.execPath, [injectionAnalyzerPath], {
  cwd: root,
  encoding: "utf8"
});
assert(analyzer.status === 0, `Codex injection analyzer failed: ${analyzer.stderr || analyzer.stdout}`);
const analysis = JSON.parse(analyzer.stdout);
assert(analysis.format === "codex-electron-host-injection-analysis", "injection analyzer returned wrong format");
assert(analysis.channels?.hostInboundChannel === "codex_desktop:browser-sidebar-runtime-message", "injection analyzer inbound channel drifted");
assert(analysis.channels?.hostOutboundChannel === "codex_desktop:message-for-view", "injection analyzer outbound channel drifted");
assert(analysis.preloadLifecycle?.browserSidebarUsesGuestWebview === true, "injection analyzer lost browser sidebar guest webview proof");
assert(analysis.preloadLifecycle?.willAttachWebviewSetsCommentPreload === true, "injection analyzer lost comment preload proof");
assert(analysis.injectionPoints?.some((point) => point.id === "load-adapter-before-codex-runtime-handler-registration"), "injection analyzer missing host adapter load point");
assert(analysis.injectionPoints?.some((point) => point.id === "send-host-state-to-comment-preload"), "injection analyzer missing host-to-view send point");

const patchOutputRoot = mkdtempSync(join(tmpdir(), "appshot-codex-host-patch-"));
try {
  const patcherRun = spawnSync(process.execPath, [
    patcherPath,
    "--output-dir",
    patchOutputRoot
  ], {
    cwd: root,
    encoding: "utf8"
  });
  assert(patcherRun.status === 0, `Codex host patcher failed: ${patcherRun.stderr || patcherRun.stdout}`);
  const patchPlan = JSON.parse(patcherRun.stdout);
  assert(patchPlan.format === "appshot-codex-electron-host-patch-plan", "patcher returned wrong format");
  assert(patchPlan.mode === "copy", "patcher did not run in copy mode");
  assert(patchPlan.changed?.main === true, "patcher did not patch Codex main bundle");
  assert(patchPlan.changed?.commentPreload === true, "patcher did not patch Codex comment preload");
  const patchedMain = readFileSync(patchPlan.patchedFiles.main, "utf8");
  const patchedPreload = readFileSync(patchPlan.patchedFiles.commentPreload, "utf8");
  assert(patchedMain.includes(patchPlan.markers.main), "patched main bundle missing AppShot marker");
  assert(patchedMain.includes("installAppShotCodexHostBridge"), "patched main bundle missing adapter install call");
  assert(patchedPreload.includes(patchPlan.markers.preload), "patched comment preload missing AppShot marker");
  assert(patchedPreload.includes("exposeInMainWorld(\"codex_desktop\""), "patched comment preload missing codex_desktop exposure");
  const patchedAnalyzer = spawnSync(process.execPath, [injectionAnalyzerPath], {
    cwd: root,
    env: Object.assign({}, process.env, {
      CODEX_EVIDENCE_ROOT: patchOutputRoot
    }),
    encoding: "utf8"
  });
  assert(patchedAnalyzer.status === 0, `patched Codex analyzer failed: ${patchedAnalyzer.stderr || patchedAnalyzer.stdout}`);
  const patchedAnalysis = JSON.parse(patchedAnalyzer.stdout);
  assert(patchedAnalysis.channels?.hostOutboundChannel === "codex_desktop:message-for-view", "patched analysis lost host outbound channel");
} finally {
  rmSync(patchOutputRoot, {
    recursive: true,
    force: true
  });
}

bridge.dispose();
assert(ipcMain.handle === originalHandle, "adapter dispose did not restore ipcMain.handle");

console.log("codex host integration: ok");
