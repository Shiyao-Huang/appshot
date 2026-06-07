import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const extensionDir = path.join(root, "browser-extension", "appshot-bridge");
const manifest = JSON.parse(fs.readFileSync(path.join(extensionDir, "manifest.json"), "utf8"));
const pageBridge = fs.readFileSync(path.join(extensionDir, "page-bridge.js"), "utf8");
const content = fs.readFileSync(path.join(extensionDir, "content.js"), "utf8");
const background = fs.readFileSync(path.join(extensionDir, "background.js"), "utf8");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

assert(manifest.manifest_version === 3, "manifest must be MV3");
assert(manifest.background?.service_worker === "background.js", "manifest must register background service worker");
assert(JSON.stringify(manifest).includes("page-bridge.js"), "manifest must include page bridge");
assert(JSON.stringify(manifest).includes("content.js"), "manifest must include content bridge");

for (const [name, text] of [
  ["page-bridge.js", pageBridge],
  ["content.js", content],
  ["background.js", background]
]) {
  for (const needle of [
    "appshot-browser-runtime-bridge",
    "codex_desktop:browser-sidebar-runtime-message"
  ]) {
    assert(text.includes(needle), `${name} missing ${needle}`);
  }
}

for (const needle of [
  "sendMessageToHost",
  "subscribeToHostMessages",
  "window.codex_desktop"
]) {
  assert(pageBridge.includes(needle), `page-bridge.js missing ${needle}`);
}

const messageListeners = [];
const postedMessages = [];
const windowObject = {
  location: { href: "https://example.test/bridge" },
  __appshotRuntimeEventLog: [],
  addEventListener(type, listener) {
    if (type === "message") {
      messageListeners.push(listener);
    }
  },
  postMessage(payload) {
    postedMessages.push(payload);
  }
};
windowObject.window = windowObject;

const documentObject = {
  title: "Bridge Fixture",
  addEventListener() {}
};

vm.runInNewContext(pageBridge, {
  window: windowObject,
  document: documentObject,
  Date,
  Math
}, {
  filename: "page-bridge.js"
});

assert(windowObject.codex_desktop, "page bridge did not create window.codex_desktop");
assert(typeof windowObject.codex_desktop.sendMessageToHost === "function", "missing sendMessageToHost");
assert(typeof windowObject.codex_desktop.subscribeToHostMessages === "function", "missing subscribeToHostMessages");
assert(windowObject.__appshotBrowserBridgeHost.owner === "browser-extension", "host owner drifted");
assert(windowObject.__appshotBrowserBridgeHost.transport === "window.postMessage+extension-runtime", "host transport drifted");

let received = null;
const unsubscribe = windowObject.codex_desktop.subscribeToHostMessages((message) => {
  received = message;
});
const event = windowObject.codex_desktop.sendMessageToHost({ type: "ping" });
assert(event.type === "browser-sidebar-runtime-message", "sendMessageToHost did not return a runtime message event");
assert(windowObject.__appshotRuntimeEventLog.some((entry) => entry.type === "browser-sidebar-runtime-message"), "runtime log missing host message event");
assert(postedMessages.some((entry) => entry.type === "appshot-host-message"), "page bridge did not post host message to extension");

for (const listener of messageListeners) {
  listener({
    source: windowObject,
    data: {
      source: "appshot-browser-runtime-bridge",
      direction: "extension-to-page",
      type: "codex_desktop:browser-sidebar-runtime-message",
      requestId: "fixture-host-message",
      message: { type: "host-sync" }
    }
  });
}

assert(received?.message?.type === "host-sync", "subscriber did not receive host message");
unsubscribe();

console.log("browser bridge extension: ok");
