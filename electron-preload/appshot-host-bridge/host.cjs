const source = "appshot-electron-preload-bridge";
const bridgeEventSource = "appshot-browser-runtime-bridge";
const hostChannel = "codex_desktop:browser-sidebar-runtime-message";
const hostOwner = "electron-preload";
const hostTransport = "electron-ipc";
const maxEvents = 200;

function createState() {
  return {
    source,
    bridgeEventSource,
    hostChannel,
    hostOwner,
    hostTransport,
    electronHostBridgeAvailable: true,
    liveEventStreamAvailable: true,
    eventCount: 0,
    events: []
  };
}

function appendEvent(state, event) {
  if (!event || typeof event !== "object") {
    return state.events;
  }
  state.events.push(Object.assign({
    source: bridgeEventSource,
    bridgeSource: source,
    bridgeEvent: true,
    candidate: false,
    hostChannel,
    hostOwner,
    hostTransport,
    electronHostBridgeAvailable: true
  }, event));
  if (state.events.length > maxEvents) {
    state.events.splice(0, state.events.length - maxEvents);
  }
  state.eventCount = state.events.length;
  return state.events;
}

function sendToWebContents(webContents, payload) {
  if (!webContents || typeof webContents.send !== "function" || webContents.isDestroyed?.()) {
    return false;
  }
  webContents.send(hostChannel, Object.assign({
    source,
    type: hostChannel,
    hostChannel,
    hostOwner,
    hostTransport
  }, payload || {}));
  return true;
}

function installAppShotElectronHostBridge(ipcMain, options = {}) {
  if (!ipcMain || typeof ipcMain.on !== "function") {
    throw new Error("installAppShotElectronHostBridge requires Electron ipcMain");
  }

  const state = createState();
  const onMessage = (event, payload = {}) => {
    appendEvent(state, payload.event);
    if (options.echoToSender !== false && event && event.sender) {
      sendToWebContents(event.sender, {
        requestId: payload.requestId || "",
        message: payload.message,
        event: payload.event
      });
    }
    if (typeof options.onMessage === "function") {
      options.onMessage(payload, event, state);
    }
  };

  ipcMain.on(hostChannel, onMessage);

  return {
    source,
    hostChannel,
    hostOwner,
    hostTransport,
    getState() {
      return Object.assign({}, state, {
        events: state.events.slice(-80)
      });
    },
    sendToWebContents(webContents, payload) {
      return sendToWebContents(webContents, payload);
    },
    dispose() {
      if (typeof ipcMain.removeListener === "function") {
        ipcMain.removeListener(hostChannel, onMessage);
      }
    }
  };
}

module.exports = {
  installAppShotElectronHostBridge,
  hostChannel,
  hostOwner,
  hostTransport,
  source
};
