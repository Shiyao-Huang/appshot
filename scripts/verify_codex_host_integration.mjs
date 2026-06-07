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
const materializerPath = join(root, "scripts", "materialize_codex_host_patch_for_appshot.mjs");
const evidenceRoot = resolve(root, "..", "codex-522", "mac-app");
const eventsPath = join(evidenceRoot, "artifacts", "comment-preload-runtime-events-522.txt");
const snippetsPath = join(evidenceRoot, "appshots-evidence", "522-appshots-snippets.js");
const mainBundlePath = join(evidenceRoot, "asar-522", ".vite", "build", "main-DVEWN1ng.js");
const commentPreloadPath = join(evidenceRoot, "asar-522", ".vite", "build", "comment-preload.js");
const alternateAsarRoot = join(evidenceRoot, "asar-3003");
const packedCodexApp = join(evidenceRoot, "extracted", "Codex-522.app");

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
  materializerPath,
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
const materializer = readFileSync(materializerPath, "utf8");
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
  "materialize_codex_host_patch_for_appshot",
  "--asar-root",
  "--codex-app",
  "packed app.asar",
  "app.asar.extracted",
  "copy-app-bundle",
  "sourceMainBundle",
  "browser-sidebar-runtime-sync",
  "browser-sidebar-runtime-message"
]) {
  assert(
    adapterSource.includes(needle) || readme.includes(needle) || injectionAnalyzer.includes(needle) || patcher.includes(needle) || materializer.includes(needle) || events.includes(needle) || snippets.includes(needle),
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
  assert(patchPlan.sourceMainBundle === "main-DVEWN1ng.js", "patcher did not report discovered main bundle");
  assert(patchPlan.outputAsarRoot?.endsWith("asar-522"), "patcher did not report output asar root");
  assert(patchPlan.changed?.main === true, "patcher did not patch Codex main bundle");
  assert(patchPlan.changed?.commentPreload === true, "patcher did not patch Codex comment preload");
  const patchedMain = readFileSync(patchPlan.patchedFiles.main, "utf8");
  const patchedPreload = readFileSync(patchPlan.patchedFiles.commentPreload, "utf8");
  assert(patchedMain.includes(patchPlan.markers.main), "patched main bundle missing AppShot marker");
  assert(patchedMain.includes("installAppShotCodexHostBridge"), "patched main bundle missing adapter install call");
  assert(patchedMain.includes("__appshotInstallCodexHostBridge(n.ipcMain,t),n.ipcMain.handle(Ts,"), "patched main bundle did not install before browser runtime handler");
  assert(patchedPreload.includes(patchPlan.markers.preload), "patched comment preload missing AppShot marker");
  assert(patchedPreload.includes("exposeInMainWorld(\"codex_desktop\""), "patched comment preload missing codex_desktop exposure");
  for (const file of [patchPlan.patchedFiles.main, patchPlan.patchedFiles.commentPreload]) {
    const syntaxCheck = spawnSync(process.execPath, ["--check", file], {
      cwd: root,
      encoding: "utf8"
    });
    assert(syntaxCheck.status === 0, `patched Codex JS syntax check failed for ${file}: ${syntaxCheck.stderr || syntaxCheck.stdout}`);
  }
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

if (existsSync(alternateAsarRoot)) {
  const alternateAnalysis = spawnSync(process.execPath, [
    injectionAnalyzerPath,
    "--asar-root",
    alternateAsarRoot,
    "--compact"
  ], {
    cwd: root,
    encoding: "utf8"
  });
  assert(alternateAnalysis.status === 0, `alternate Codex asar analyzer failed: ${alternateAnalysis.stderr || alternateAnalysis.stdout}`);
  const alternatePayload = JSON.parse(alternateAnalysis.stdout);
  assert(alternatePayload.files?.mainBundle === "main-BLTY-mbJ.js", "alternate analyzer did not discover hashed main bundle");
  assert(alternatePayload.anchors?.main?.some((entry) => entry.name === "browser sidebar webview preload assignment" && entry.match?.includes(".preload=")), "alternate analyzer lost semantic preload assignment proof");

  const alternatePatchRoot = mkdtempSync(join(tmpdir(), "appshot-codex-host-patch-alt-"));
  try {
    const alternatePatcherRun = spawnSync(process.execPath, [
      patcherPath,
      "--asar-root",
      alternateAsarRoot,
      "--output-dir",
      alternatePatchRoot
    ], {
      cwd: root,
      encoding: "utf8"
    });
    assert(alternatePatcherRun.status === 0, `alternate Codex host patcher failed: ${alternatePatcherRun.stderr || alternatePatcherRun.stdout}`);
    const alternatePatch = JSON.parse(alternatePatcherRun.stdout);
    assert(alternatePatch.sourceMainBundle === "main-BLTY-mbJ.js", "alternate patcher did not discover hashed main bundle");
    for (const file of [alternatePatch.patchedFiles.main, alternatePatch.patchedFiles.commentPreload]) {
      const syntaxCheck = spawnSync(process.execPath, ["--check", file], {
        cwd: root,
        encoding: "utf8"
      });
      assert(syntaxCheck.status === 0, `alternate patched Codex JS syntax check failed for ${file}: ${syntaxCheck.stderr || syntaxCheck.stdout}`);
    }
    const alternatePatchedAnalysis = spawnSync(process.execPath, [
      injectionAnalyzerPath,
      "--asar-root",
      alternatePatch.outputAsarRoot,
      "--compact"
    ], {
      cwd: root,
      encoding: "utf8"
    });
    assert(alternatePatchedAnalysis.status === 0, `alternate patched Codex analyzer failed: ${alternatePatchedAnalysis.stderr || alternatePatchedAnalysis.stdout}`);
  } finally {
    rmSync(alternatePatchRoot, {
      recursive: true,
      force: true
    });
  }
}

if (existsSync(packedCodexApp)) {
  const materializedRoot = mkdtempSync(join(tmpdir(), "appshot-codex-host-materialized-"));
  try {
    const materializerRun = spawnSync(process.execPath, [
      materializerPath,
      "--codex-app",
      packedCodexApp,
      "--output-dir",
      materializedRoot
    ], {
      cwd: root,
      encoding: "utf8"
    });
    assert(materializerRun.status === 0, `Codex host materializer failed: ${materializerRun.stderr || materializerRun.stdout}`);
    const materialized = JSON.parse(materializerRun.stdout);
    assert(materialized.format === "appshot-codex-host-materialization", "materializer returned wrong format");
    assert(materialized.sourceKind === "codex-app-packed-asar", "materializer did not detect packed Codex app asar");
    assert(materialized.extraction?.fileCount > 100, "materializer extracted too few asar files");
    assert(materialized.extraction?.unpackedFileCount > 0, "materializer did not copy unpacked asar sidecar files");
    assert(materialized.patch?.changed?.main === true, "materializer did not patch extracted Codex main bundle");
    assert(materialized.patch?.changed?.commentPreload === true, "materializer did not patch extracted Codex comment preload");
    assert(materialized.syntaxChecks?.length === 2 && materialized.syntaxChecks.every((entry) => entry.ok === true), "materializer did not syntax-check patched Codex JS");
    assert(materialized.analysis?.channels?.hostInboundChannel === "codex_desktop:browser-sidebar-runtime-message", "materializer patched analysis lost host inbound channel");
    assert(materialized.privateHostStillRequiresLaunchingPatchedCodex === true, "materializer should not claim live private host attachment");
  } finally {
    rmSync(materializedRoot, {
      recursive: true,
      force: true
    });
  }

  const packedAppAnalysis = spawnSync(process.execPath, [
    injectionAnalyzerPath,
    "--codex-app",
    packedCodexApp,
    "--compact"
  ], {
    cwd: root,
    encoding: "utf8"
  });
  assert(packedAppAnalysis.status !== 0, "packed Codex app analysis should require explicit asar extraction");
  assert((packedAppAnalysis.stderr || packedAppAnalysis.stdout).includes("packed app.asar"), "packed Codex app analysis did not explain packed asar requirement");
}

bridge.dispose();
assert(ipcMain.handle === originalHandle, "adapter dispose did not restore ipcMain.handle");

console.log("codex host integration: ok");
