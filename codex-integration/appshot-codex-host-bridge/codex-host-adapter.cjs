const {
  installAppShotElectronHostBridge,
  hostChannel: appShotElectronHostChannel,
  hostOwner: electronHostOwner,
  hostTransport: electronHostTransport
} = require("../../electron-preload/appshot-host-bridge/host.cjs");

const source = "appshot-codex-electron-host-integration";
const bridgeEventSource = "appshot-browser-runtime-bridge";
const codexHostChannelAnchor = "codex_desktop:browser-sidebar-runtime-message";
const hostChannel = codexHostChannelAnchor;
const hostInboundChannel = codexHostChannelAnchor;
const hostOutboundChannel = "codex_desktop:message-for-view";
const hostToViewChannel = hostOutboundChannel;
const hostOwner = "codex-electron-host";
const hostTransport = "codex-electron-ipc+appshot-electron-ipc";
const hostAPI = ["sendMessageToHost", "subscribeToHostMessages"];
const diagnosticAnchor = "host-managed-browser-state";
const ipcPattern = "ipcRenderer.invoke/ipcMain.handle + webContents.send/ipcRenderer.on";
const maxEvents = 200;

if (appShotElectronHostChannel !== codexHostChannelAnchor) {
  throw new Error(`AppShot Electron host channel drifted: ${appShotElectronHostChannel}`);
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
    hostInboundChannel,
    hostOutboundChannel,
    hostToViewChannel,
    hostOwner,
    hostTransport,
    ipcPattern,
    underlyingHostOwner: electronHostOwner,
    underlyingHostTransport: electronHostTransport,
    requiredCodexSideIntegration: true,
    privateCodexWebviewHostAttached: true,
    hostManagedBrowserStateAvailable: typeof options.getBrowserState === "function",
    ipcMainHandleTapInstalled: false,
    codexRuntimeHandlerWrapped: false,
    codexRuntimeMessageObserved: false,
    requiresLoadBeforeCodexHandlerRegistration: true,
    liveEventStreamAvailable: true,
    eventCount: 0,
    events: []
  };
}

function normalizeRuntimeEvent(payload) {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  if (payload.event && typeof payload.event === "object") {
    return payload.event;
  }
  if (payload.state && typeof payload.state === "object" && typeof payload.state.type === "string") {
    return payload.state;
  }
  if (typeof payload.type === "string" && payload.type.startsWith("browser-sidebar-runtime-")) {
    return payload;
  }
  return {
    type: "browser-sidebar-runtime-message",
    message: payload
  };
}

function appendEvent(state, event, fields = {}) {
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
    hostInboundChannel,
    hostOutboundChannel,
    hostOwner,
    hostTransport,
    ipcPattern,
    codexHostIntegration: true,
    privateCodexWebviewHostAttached: true
  }, event, fields);
  state.events.push(codexEvent);
  if (state.events.length > maxEvents) {
    state.events.splice(0, state.events.length - maxEvents);
  }
  state.eventCount = state.events.length;
  state.codexRuntimeMessageObserved = true;
  state.lastRuntimeMessageType = codexEvent.type;
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
    hostInboundChannel,
    hostOutboundChannel,
    hostOwner,
    hostTransport,
    ipcPattern,
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

function sendToWebContents(webContents, channel, payload) {
  if (!webContents || typeof webContents.send !== "function" || webContents.isDestroyed?.()) {
    return false;
  }
  webContents.send(channel, payload);
  return true;
}

function installAppShotCodexHostBridge(ipcMain, options = {}) {
  if (!ipcMain || (typeof ipcMain.on !== "function" && typeof ipcMain.handle !== "function")) {
    throw new Error("installAppShotCodexHostBridge requires Electron ipcMain");
  }

  const codexState = createCodexHostState(options);

  const observeCodexRuntimeMessage = (payload, event, metadata = {}) => {
    const runtimeEvent = normalizeRuntimeEvent(payload);
    const events = appendEvent(codexState, runtimeEvent, {
      ipcPattern: metadata.ipcPattern || ipcPattern
    });
    const codexEvent = events.at(-1) || null;
    if (typeof options.onCodexRuntimeMessage === "function") {
      options.onCodexRuntimeMessage(payload, event, codexState, metadata);
    }
    if (typeof options.onMessage === "function") {
      options.onMessage(payload, event, codexState, metadata);
    }
    return codexEvent;
  };

  const electronBridge = typeof ipcMain.on === "function"
    ? installAppShotElectronHostBridge(ipcMain, {
        echoToSender: options.echoToSender,
        onMessage(payload, event, electronState) {
          return observeCodexRuntimeMessage(payload, event, {
            electronState,
            ipcPattern: "ipcRenderer.send/ipcMain.on"
          });
        }
      })
    : null;

  let restoreIpcMainHandle = null;
  const bridge = {
    source,
    diagnosticAnchor,
    hostChannel,
    hostInboundChannel,
    hostOutboundChannel,
    hostToViewChannel,
    hostAPI: hostAPI.slice(),
    hostOwner,
    hostTransport,
    ipcPattern,
    electronBridge,
    observeCodexRuntimeMessage,
    wrapCodexRuntimeMessageHandler(handler) {
      if (typeof handler !== "function") {
        throw new Error("wrapCodexRuntimeMessageHandler requires a handler function");
      }
      codexState.codexRuntimeHandlerWrapped = true;
      return async function appshotCodexRuntimeMessageHandler(event, payload, ...rest) {
        observeCodexRuntimeMessage(payload, event, {
          ipcPattern
        });
        return handler.call(this, event, payload, ...rest);
      };
    },
    getState() {
      const electronState = electronBridge && typeof electronBridge.getState === "function"
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
    sendCodexRuntimeEvent(webContents, event = {}) {
      const runtimeEvent = Object.assign({
        source: bridgeEventSource,
        bridgeSource: source,
        bridgeEvent: true,
        candidate: false,
        capturedAt: now(),
        hostChannel,
        hostInboundChannel,
        hostOutboundChannel,
        hostOwner,
        hostTransport,
        ipcPattern,
        codexHostIntegration: true,
        privateCodexWebviewHostAttached: true
      }, event || {});
      appendEvent(codexState, runtimeEvent);
      return sendToWebContents(webContents, hostOutboundChannel, runtimeEvent);
    },
    sendCodexHostState(webContents, browserState = {}) {
      const state = typeof options.getBrowserState === "function"
        ? options.getBrowserState(browserState)
        : browserState;
      const syncEvent = createBrowserRuntimeSync(state);
      appendEvent(codexState, syncEvent);
      return sendToWebContents(webContents, hostOutboundChannel, syncEvent);
    },
    dispose() {
      if (typeof restoreIpcMainHandle === "function") {
        restoreIpcMainHandle();
      }
      if (electronBridge && typeof electronBridge.dispose === "function") {
        electronBridge.dispose();
      }
    }
  };

  restoreIpcMainHandle = patchIpcMainHandle(ipcMain, bridge, codexState, options);

  return bridge;
}

function patchIpcMainHandle(ipcMain, bridge, codexState, options) {
  if (options.patchIpcMainHandle === false || typeof ipcMain.handle !== "function") {
    return null;
  }
  const originalHandle = ipcMain.handle;
  if (originalHandle.__appshotCodexHostBridgePatched === true) {
    return null;
  }

  function appshotCodexPatchedHandle(channel, handler) {
    if (channel === hostInboundChannel && typeof handler === "function") {
      codexState.codexRuntimeHandlerWrapped = true;
      return originalHandle.call(this, channel, bridge.wrapCodexRuntimeMessageHandler(handler));
    }
    return originalHandle.apply(this, arguments);
  }

  Object.defineProperty(appshotCodexPatchedHandle, "__appshotCodexHostBridgePatched", {
    value: true
  });
  Object.defineProperty(appshotCodexPatchedHandle, "__appshotOriginalHandle", {
    value: originalHandle
  });

  ipcMain.handle = appshotCodexPatchedHandle;
  codexState.ipcMainHandleTapInstalled = true;
  return () => {
    if (ipcMain.handle === appshotCodexPatchedHandle) {
      ipcMain.handle = originalHandle;
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
  hostInboundChannel,
  hostOutboundChannel,
  hostToViewChannel,
  hostOwner,
  hostTransport,
  ipcPattern,
  diagnosticAnchor,
  source
};
