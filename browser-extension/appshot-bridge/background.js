const source = "appshot-browser-runtime-bridge";
const hostChannel = "codex_desktop:browser-sidebar-runtime-message";
const maxEvents = 200;
const eventsByFrame = new Map();

function keyForSender(sender) {
  const tabId = sender && sender.tab && typeof sender.tab.id === "number"
    ? sender.tab.id
    : "unknown-tab";
  const frameId = sender && typeof sender.frameId === "number"
    ? sender.frameId
    : 0;
  return `${tabId}:${frameId}`;
}

function appendEvent(key, event) {
  const events = eventsByFrame.get(key) || [];
  events.push(event);
  if (events.length > maxEvents) {
    events.splice(0, events.length - maxEvents);
  }
  eventsByFrame.set(key, events);
  return events;
}

function stateFor(key) {
  const events = eventsByFrame.get(key) || [];
  return {
    ok: true,
    source,
    hostChannel,
    hostOwner: "browser-extension",
    hostTransport: "window.postMessage+extension-runtime",
    extensionHelperAvailable: true,
    liveEventStreamAvailable: true,
    eventCount: events.length,
    events: events.slice(-80)
  };
}

function sendToFrame(sender, message) {
  if (!globalThis.chrome || !chrome.tabs || !sender || !sender.tab || typeof sender.tab.id !== "number") {
    return;
  }
  try {
    chrome.tabs.sendMessage(sender.tab.id, Object.assign({ source }, message), {
      frameId: typeof sender.frameId === "number" ? sender.frameId : 0
    });
  } catch (_) {}
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.source !== source) {
    return false;
  }

  const key = keyForSender(sender);
  const payload = message.payload || {};
  const event = payload.event;

  if (message.type === "appshot-bridge-event" && event) {
    appendEvent(key, event);
    sendResponse(stateFor(key));
    return false;
  }

  if (message.type === "appshot-host-message") {
    if (event) {
      appendEvent(key, event);
    }
    sendToFrame(sender, {
      type: hostChannel,
      requestId: message.requestId || payload.requestId || "",
      message: payload.message,
      event
    });
    sendResponse(stateFor(key));
    return false;
  }

  if (message.type === "appshot-host-subscribe" || message.type === "appshot-host-unsubscribe") {
    sendResponse(stateFor(key));
    return false;
  }

  if (message.type === "appshot-get-state") {
    sendResponse(stateFor(key));
    return false;
  }

  if (message.type === "appshot-clear-log") {
    eventsByFrame.set(key, []);
    sendResponse(stateFor(key));
    return false;
  }

  sendResponse(stateFor(key));
  return false;
});
