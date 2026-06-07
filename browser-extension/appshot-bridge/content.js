(() => {
  const source = "appshot-browser-runtime-bridge";
  const hostChannel = "codex_desktop:browser-sidebar-runtime-message";
  const pageDirection = "page-to-extension";
  const hostDirection = "extension-to-page";
  const runtime = globalThis.browser && globalThis.browser.runtime
    ? globalThis.browser.runtime
    : globalThis.chrome && globalThis.chrome.runtime
      ? globalThis.chrome.runtime
      : null;

  function runtimeSendMessage(message) {
    if (!runtime || typeof runtime.sendMessage !== "function") {
      return Promise.resolve({ ok: false, reason: "runtimeUnavailable" });
    }
    if (globalThis.browser && globalThis.browser.runtime) {
      return runtime.sendMessage(message).catch((error) => ({
        ok: false,
        error: String(error && error.message ? error.message : error)
      }));
    }
    return new Promise((resolve) => {
      try {
        runtime.sendMessage(message, (response) => {
          const lastError = runtime.lastError;
          if (lastError) {
            resolve({ ok: false, error: lastError.message || String(lastError) });
          } else {
            resolve(response || { ok: true });
          }
        });
      } catch (error) {
        resolve({ ok: false, error: String(error && error.message ? error.message : error) });
      }
    });
  }

  function postToPage(payload) {
    window.postMessage(Object.assign({
      source,
      direction: hostDirection,
      hostChannel
    }, payload), "*");
  }

  function injectPageBridgeFallback() {
    if (!runtime || typeof runtime.getURL !== "function" || !document) {
      return;
    }
    try {
      const script = document.createElement("script");
      script.src = runtime.getURL("page-bridge.js");
      script.async = false;
      script.dataset.appshotBrowserBridge = "true";
      const parent = document.documentElement || document.head || document.body;
      if (parent && typeof parent.appendChild === "function") {
        parent.appendChild(script);
        script.remove();
      }
    } catch (_) {}
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.source !== source || data.direction !== pageDirection) return;
    runtimeSendMessage({
      source,
      type: data.type,
      hostChannel,
      hostOwner: data.hostOwner || "browser-extension",
      hostTransport: data.hostTransport || "window.postMessage+extension-runtime",
      pageUrl: data.pageUrl || window.location.href,
      title: data.title || document.title || "",
      requestId: data.requestId || "",
      payload: data.payload || {}
    }).then((response) => {
      postToPage({
        type: "appshot-extension-response",
        requestId: data.requestId || "",
        response
      });
    });
  });

  if (runtime && runtime.onMessage && typeof runtime.onMessage.addListener === "function") {
    runtime.onMessage.addListener((message, _sender, sendResponse) => {
      if (!message || message.source !== source) return false;
      postToPage({
        type: message.type || hostChannel,
        requestId: message.requestId || "",
        message: message.message,
        event: message.event
      });
      if (typeof sendResponse === "function") {
        sendResponse({ ok: true });
      }
      return false;
    });
  }

  injectPageBridgeFallback();
})();
