import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { EventEmitter } from "node:events";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const bridgeDir = path.join(root, "electron-preload", "appshot-host-bridge");
const preloadPath = path.join(bridgeDir, "preload.cjs");
const hostPath = path.join(bridgeDir, "host.cjs");
const preloadSource = fs.readFileSync(preloadPath, "utf8");
const hostSource = fs.readFileSync(hostPath, "utf8");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

for (const [name, text] of [
  ["preload.cjs", preloadSource],
  ["host.cjs", hostSource]
]) {
  for (const needle of [
    "codex_desktop:browser-sidebar-runtime-message",
    "electron-preload",
    "electron-ipc"
  ]) {
    assert(text.includes(needle), `${name} missing ${needle}`);
  }
}

for (const needle of [
  "sendMessageToHost",
  "subscribeToHostMessages",
  "codex_desktop"
]) {
  assert(preloadSource.includes(needle), `preload.cjs missing ${needle}`);
}

assert(hostSource.includes("installAppShotElectronHostBridge"), "host.cjs missing installAppShotElectronHostBridge");

const ipcRenderer = new EventEmitter();
const sent = [];
ipcRenderer.send = (channel, payload) => {
  sent.push({ channel, payload });
};
ipcRenderer.removeListener = ipcRenderer.removeListener.bind(ipcRenderer);

const exposed = {};
const context = {
  console,
  Date,
  Math,
  globalThis: {},
  require(name) {
    if (name === "electron") {
      return {
        ipcRenderer,
        contextBridge: {
          exposeInMainWorld(key, value) {
            exposed[key] = value;
            context.globalThis[key] = value;
          }
        }
      };
    }
    throw new Error(`unexpected require: ${name}`);
  }
};
context.globalThis.globalThis = context.globalThis;

vm.runInNewContext(preloadSource, context, { filename: "preload.cjs" });

assert(exposed.codex_desktop, "preload did not expose codex_desktop");
assert(typeof exposed.codex_desktop.sendMessageToHost === "function", "sendMessageToHost missing");
assert(typeof exposed.codex_desktop.subscribeToHostMessages === "function", "subscribeToHostMessages missing");
assert(exposed.__appshotBrowserBridgeHost.owner === "electron-preload", "host owner drifted");
assert(exposed.__appshotBrowserBridgeHost.transport === "electron-ipc", "host transport drifted");

let received = null;
const unsubscribe = exposed.codex_desktop.subscribeToHostMessages((payload) => {
  received = payload;
});
const event = exposed.codex_desktop.sendMessageToHost({ type: "ping" });
assert(event.type === "browser-sidebar-runtime-message", "sendMessageToHost returned wrong event type");
assert(sent.some((entry) => entry.channel === "codex_desktop:browser-sidebar-runtime-message"), "ipcRenderer did not send host channel");
ipcRenderer.emit("codex_desktop:browser-sidebar-runtime-message", {}, {
  message: { type: "host-sync" }
});
assert(received?.message?.type === "host-sync", "subscriber did not receive host message");
unsubscribe();

const hostModule = { exports: {} };
const ipcMain = new EventEmitter();
ipcMain.on = ipcMain.on.bind(ipcMain);
ipcMain.removeListener = ipcMain.removeListener.bind(ipcMain);
vm.runInNewContext(hostSource, {
  module: hostModule,
  exports: hostModule.exports,
  require(name) {
    throw new Error(`unexpected host require: ${name}`);
  }
}, { filename: "host.cjs" });

const bridge = hostModule.exports.installAppShotElectronHostBridge(ipcMain);
assert(bridge.hostOwner === "electron-preload", "main bridge owner drifted");
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
  requestId: "fixture",
  message: { type: "ping" },
  event
});
assert(bridge.getState().eventCount === 1, "host bridge did not log event");
assert(echoed?.channel === "codex_desktop:browser-sidebar-runtime-message", "host bridge did not echo to sender");
bridge.dispose();

console.log("electron host bridge: ok");
