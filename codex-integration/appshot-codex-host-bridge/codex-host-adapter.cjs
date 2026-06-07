const {
  installAppShotElectronHostBridge,
  hostChannel,
  hostOwner: electronHostOwner,
  hostTransport: electronHostTransport
} = require("../../electron-preload/appshot-host-bridge/host.cjs");

const source = "appshot-codex-electron-host-integration";
const bridgeEventSource = "appshot-browser-runtime-bridge";
const codexHostChannelAnchor = "codex_desktop:browser-sidebar-runtime-message";
const hostOwner = "codex-electron-host";
const hostTransport = "codex-electron-ipc+appshot-electron-ipc";
const hostAPI = ["sendMessageToHost", "subscribeToHostMessages"];
const diagnosticAnchor = "host-managed-browser-state";
const maxEvents = 200;

if (hostChannel !== codexHostChannelAnchor) {
  throw new Error(`AppShot Codex host channel drifted: ${hostChannel}`);
}

function now() {
  return new Date().toISOString();
}

function createCodexHostState(options = {}) {
  return {
    format: "codex-electron-host-integration-status",
    source,
    diagnosticAnchor,
    hostAPI: hostAPI.slice(),
    hostChannel,
    hostOwner,
    hostTransport,
    underlyingHostOwner: electronHostOwner,
    underlyingHostTransport: electronHostTransport,
    requiredCodexSideIntegration: true,
    privateCodexWebviewHostAttached: true,
    hostManagedBrowserStateAvailable: typeof options.getBrowserState === "function",
    liveEventStreamAvailable: true,
    eventCount: 0,
    events: []
  };
}

function appendEvent(state, event) {
  if (!event || typeof event !== "object") {
    return state.events;
  }
  const codexEvent = Object.assign({
    type: "browser-sidebar-runtime-message",
    source: bridgeEventSource,
    bridgeSource: source,
    bridgeEvent: true,
    candidate: false,
    capturedAt: now(),
    hostChannel,
    hostOwner,
    hostTransport,
    codexHostIntegration: true,
    privateCodexWebviewHostAttached: true
  }, event);
  state.events.push(codexEvent);
  if (state.events.length > maxEvents) {
    state.events.splice(0, state.events.length - maxEvents);
  }
  state.eventCount = state.events.length;
  return state.events;
}

function createBrowserRuntimeSync(browserState = {}) {
  return Object.assign({
    type: "browser-sidebar-runtime-sync",
    source: bridgeEventSource,
    bridgeSource: source,
    bridgeEvent: true,
    candidate: false,
    capturedAt: now(),
    hostChannel,
    hostOwner,
    hostTransport,
    codexHostIntegration: true,
    privateCodexWebviewHostAttached: true,
    interactionMode: "comment",
    annotationEditorMode: "comment",
    isAgentControllingBrowser: false,
    canUseTweaks: true,
    isDesignModifierPressed: false,
    isOriginalViewEnabled: false,
    isTweaksEditorOpen: false,
    comments: []
  }, browserState || {});
}

function installAppShotCodexHostBridge(ipcMain, options = {}) {
  if (!ipcMain || typeof ipcMain.on !== "function") {
    throw new Error("installAppShotCodexHostBridge requires Electron ipcMain");
  }

  const codexState = createCodexHostState(options);
  const electronBridge = installAppShotElectronHostBridge(ipcMain, {
    echoToSender: options.echoToSender,
    onMessage(payload, event, electronState) {
      const codexEvent = appendEvent(codexState, payload && payload.event);
      if (typeof options.onCodexRuntimeMessage === "function") {
        options.onCodexRuntimeMessage(payload, event, codexState, electronState);
      }
      if (typeof options.onMessage === "function") {
        options.onMessage(payload, event, codexState, electronState);
      }
      return codexEvent;
    }
  });

  return {
    source,
    diagnosticAnchor,
    hostChannel,
    hostAPI: hostAPI.slice(),
    hostOwner,
    hostTransport,
    electronBridge,
    getState() {
      const electronState = typeof electronBridge.getState === "function"
        ? electronBridge.getState()
        : {};
      return Object.assign({}, codexState, {
        events: codexState.events.slice(-80),
        electronBridge: {
          source: electronState.source || "",
          hostOwner: electronState.hostOwner || electronHostOwner,
          hostTransport: electronState.hostTransport || electronHostTransport,
          electronHostBridgeAvailable: electronState.electronHostBridgeAvailable === true,
          eventCount: electronState.eventCount || 0
        }
      });
    },
    createBrowserRuntimeSync,
    sendCodexHostState(webContents, browserState = {}) {
      const state = typeof options.getBrowserState === "function"
        ? options.getBrowserState(browserState)
        : browserState;
      const syncEvent = createBrowserRuntimeSync(state);
      appendEvent(codexState, syncEvent);
      return electronBridge.sendToWebContents(webContents, {
        source,
        type: hostChannel,
        hostChannel,
        hostOwner,
        hostTransport,
        event: syncEvent,
        state: syncEvent
      });
    },
    dispose() {
      if (typeof electronBridge.dispose === "function") {
        electronBridge.dispose();
      }
    }
  };
}

module.exports = {
  installAppShotCodexHostBridge,
  createBrowserRuntimeSync,
  createCodexHostState,
  hostAPI,
  codexHostChannelAnchor,
  hostChannel,
  hostOwner,
  hostTransport,
  diagnosticAnchor,
  source
};
