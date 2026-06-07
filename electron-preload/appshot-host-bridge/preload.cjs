(function installAppShotElectronPreloadBridge() {
  const source = "appshot-electron-preload-bridge";
  const version = "0.1.12";
  const hostChannel = "codex_desktop:browser-sidebar-runtime-message";
  const hostOwner = "electron-preload";
  const hostTransport = "electron-ipc";
  const maxEvents = 200;

  function loadElectron() {
    try {
      if (typeof require === "function") {
        return require("electron");
      }
    } catch (_) {}
    return {};
  }

  const electron = loadElectron();
  const contextBridge = electron.contextBridge;
  const ipcRenderer = electron.ipcRenderer;
  const canUseIPC = Boolean(ipcRenderer && typeof ipcRenderer.send === "function");

  function now() {
    return new Date().toISOString();
  }

  function randomId() {
    return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  }

  function runtimeLog() {
    if (!Array.isArray(globalThis.__appshotRuntimeEventLog)) {
      globalThis.__appshotRuntimeEventLog = [];
    }
    return globalThis.__appshotRuntimeEventLog;
  }

  function pushRuntimeEvent(type, fields) {
    const event = Object.assign({
      type,
      source: "appshot-browser-runtime-bridge",
      bridgeSource: source,
      bridgeEvent: true,
      candidate: false,
      capturedAt: now(),
      hostShim: true,
      hostChannel,
      hostOwner,
      hostTransport,
      electronHostBridgeAvailable: canUseIPC
    }, fields || {});
    const log = runtimeLog();
    log.push(event);
    if (log.length > maxEvents) {
      log.splice(0, log.length - maxEvents);
    }
    return event;
  }

  function hostMessagePayload(message, requestId, event) {
    return {
      source,
      type: hostChannel,
      hostChannel,
      hostOwner,
      hostTransport,
      version,
      requestId,
      message,
      event
    };
  }

  const api = {
    sendMessageToHost(message) {
      const requestId = randomId();
      const event = pushRuntimeEvent("browser-sidebar-runtime-message", {
        requestId,
        message
      });
      if (canUseIPC) {
        ipcRenderer.send(hostChannel, hostMessagePayload(message, requestId, event));
      }
      return event;
    },
    subscribeToHostMessages(callback) {
      if (typeof callback !== "function" || !ipcRenderer || typeof ipcRenderer.on !== "function") {
        return function noopUnsubscribe() {};
      }
      const handler = (_event, payload) => {
        callback(Object.assign({
          source,
          type: hostChannel,
          hostChannel,
          hostOwner,
          hostTransport
        }, payload || {}));
      };
      ipcRenderer.on(hostChannel, handler);
      return function unsubscribeFromAppShotHostMessages() {
        if (typeof ipcRenderer.removeListener === "function") {
          ipcRenderer.removeListener(hostChannel, handler);
        }
      };
    },
    getAppShotBridgeState() {
      return {
        available: true,
        electronHostBridgeAvailable: canUseIPC,
        codexDesktopShimAvailable: true,
        source,
        version,
        hostChannel,
        hostOwner,
        hostTransport,
        eventCount: runtimeLog().length,
        events: runtimeLog().slice(-80)
      };
    }
  };

  const bridgeHost = {
    available: true,
    electronHostBridgeAvailable: canUseIPC,
    codexDesktopShimAvailable: true,
    source,
    version,
    owner: hostOwner,
    transport: hostTransport,
    channel: hostChannel
  };

  globalThis.__appshotRuntimeBridgeInstalled = true;
  globalThis.__appshotRuntimeBridgeVersion = version;
  globalThis.__appshotCodexDesktopShimInstalled = true;
  globalThis.__appshotBrowserBridgeHost = bridgeHost;

  if (contextBridge && typeof contextBridge.exposeInMainWorld === "function") {
    contextBridge.exposeInMainWorld("codex_desktop", api);
    contextBridge.exposeInMainWorld("__appshotBrowserBridgeHost", bridgeHost);
  } else {
    globalThis.codex_desktop = api;
  }

  pushRuntimeEvent("browser-sidebar-runtime-sync", {
    state: {
      type: "browser-sidebar-runtime-sync",
      interactionMode: "comment",
      annotationEditorMode: "comment",
      isAgentControllingBrowser: false,
      canUseTweaks: true,
      isDesignModifierPressed: false,
      isOriginalViewEnabled: false,
      isTweaksEditorOpen: false,
      comments: []
    }
  });
})();
