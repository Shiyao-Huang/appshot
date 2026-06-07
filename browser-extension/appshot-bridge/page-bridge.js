(() => {
  const source = "appshot-browser-runtime-bridge";
  const version = "0.1.14";
  const hostChannel = "codex_desktop:browser-sidebar-runtime-message";
  const hostOwner = "browser-extension";
  const hostTransport = "window.postMessage+extension-runtime";
  const pageDirection = "page-to-extension";
  const hostDirection = "extension-to-page";
  const maxEvents = 200;

  if (window.__appshotBrowserBridgeExtensionInstalled) {
    return;
  }

  function now() {
    return new Date().toISOString();
  }

  function randomId() {
    return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  }

  function safeLocation() {
    try {
      return window.location ? window.location.href : "";
    } catch (_) {
      return "";
    }
  }

  function safeTitle() {
    try {
      return document.title || "";
    } catch (_) {
      return "";
    }
  }

  function runtimeLog() {
    if (!Array.isArray(window.__appshotRuntimeEventLog)) {
      window.__appshotRuntimeEventLog = [];
    }
    return window.__appshotRuntimeEventLog;
  }

  function subscribers() {
    if (!Array.isArray(window.__appshotCodexDesktopSubscribers)) {
      window.__appshotCodexDesktopSubscribers = [];
    }
    return window.__appshotCodexDesktopSubscribers;
  }

  function publishToExtension(type, payload) {
    window.postMessage({
      source,
      direction: pageDirection,
      type,
      hostChannel,
      hostOwner,
      hostTransport,
      version,
      requestId: payload && payload.requestId ? payload.requestId : randomId(),
      pageUrl: safeLocation(),
      title: safeTitle(),
      payload
    }, "*");
  }

  function pushRuntimeEvent(type, fields) {
    const event = Object.assign({
      type,
      source,
      bridgeEvent: true,
      candidate: false,
      capturedAt: now(),
      pageUrl: safeLocation(),
      title: safeTitle(),
      hostChannel,
      hostOwner,
      hostTransport,
      extensionHelperAvailable: true
    }, fields || {});
    const log = runtimeLog();
    log.push(event);
    if (log.length > maxEvents) {
      log.splice(0, log.length - maxEvents);
    }
    publishToExtension("appshot-bridge-event", { event });
    return event;
  }

  function notifySubscribers(message) {
    subscribers().slice().forEach((callback) => {
      try {
        callback(message);
      } catch (_) {}
    });
  }

  function installCodexDesktop() {
    const existing = window.codex_desktop;
    const api = existing && typeof existing === "object" ? existing : {};
    try {
      Object.defineProperties(api, {
        __appshotBridgeShim: { value: true, configurable: true },
        __appshotBridgeSource: { value: source, configurable: true },
        __appshotBridgeVersion: { value: version, configurable: true },
        __appshotHostOwner: { value: hostOwner, configurable: true },
        __appshotHostTransport: { value: hostTransport, configurable: true }
      });
    } catch (_) {
      api.__appshotBridgeShim = true;
      api.__appshotBridgeSource = source;
      api.__appshotBridgeVersion = version;
      api.__appshotHostOwner = hostOwner;
      api.__appshotHostTransport = hostTransport;
    }

    api.sendMessageToHost = function sendMessageToHost(message) {
      const requestId = randomId();
      const event = pushRuntimeEvent("browser-sidebar-runtime-message", {
        requestId,
        hostShim: true,
        message
      });
      publishToExtension("appshot-host-message", {
        requestId,
        message,
        event
      });
      return event;
    };

    api.subscribeToHostMessages = function subscribeToHostMessages(callback) {
      if (typeof callback !== "function") {
        return function noopUnsubscribe() {};
      }
      const list = subscribers();
      list.push(callback);
      const subscriptionId = randomId();
      publishToExtension("appshot-host-subscribe", {
        requestId: subscriptionId,
        subscriptionId
      });
      return function unsubscribeFromHostMessages() {
        const index = list.indexOf(callback);
        if (index >= 0) {
          list.splice(index, 1);
        }
        publishToExtension("appshot-host-unsubscribe", {
          requestId: subscriptionId,
          subscriptionId
        });
      };
    };

    window.codex_desktop = api;
  }

  function installInputListeners() {
    if (!document || typeof document.addEventListener !== "function") {
      return;
    }
    document.addEventListener("pointerdown", (event) => {
      const point = { x: event.clientX || 0, y: event.clientY || 0 };
      const commentId = `appshot-extension-${Date.now()}`;
      pushRuntimeEvent("browser-sidebar-runtime-open-editor", {
        commentId,
        point,
        editorMode: event.altKey ? "design" : "comment"
      });
      pushRuntimeEvent("browser-sidebar-runtime-create-comment-at-point", {
        commentId,
        point
      });
    }, true);
    document.addEventListener("keydown", (event) => {
      if (event.key !== "Alt" && event.key !== "Option") return;
      pushRuntimeEvent("browser-sidebar-runtime-design-modifier-state", {
        isDesignModifierPressed: true
      });
    }, true);
    document.addEventListener("keyup", (event) => {
      if (event.key !== "Alt" && event.key !== "Option") return;
      pushRuntimeEvent("browser-sidebar-runtime-design-modifier-state", {
        isDesignModifierPressed: false
      });
    }, true);
    document.addEventListener("dragstart", (event) => {
      const target = event.target && event.target.closest ? event.target.closest("img") : null;
      const sourceUrl = target ? target.currentSrc || target.src || "" : "";
      if (!sourceUrl) return;
      pushRuntimeEvent("browser-sidebar-runtime-image-drag-started", {
        sourceUrl
      });
    }, true);
    document.addEventListener("dragend", (event) => {
      const target = event.target && event.target.closest ? event.target.closest("img") : null;
      const sourceUrl = target ? target.currentSrc || target.src || "" : "";
      if (!sourceUrl) return;
      pushRuntimeEvent("browser-sidebar-runtime-image-drag-ended", {
        sourceUrl
      });
    }, true);
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    const data = event.data;
    if (!data || data.source !== source || data.direction !== hostDirection) return;
    notifySubscribers({
      type: data.type || hostChannel,
      source,
      hostOwner,
      hostTransport,
      hostChannel,
      requestId: data.requestId || "",
      message: data.message,
      event: data.event
    });
  });

  window.__appshotRuntimeBridgeInstalled = true;
  window.__appshotRuntimeBridgeVersion = version;
  window.__appshotCodexDesktopShimInstalled = true;
  window.__appshotBrowserBridgeExtensionInstalled = true;
  window.__appshotBrowserBridgeHost = {
    available: true,
    extensionHelperAvailable: true,
    owner: hostOwner,
    transport: hostTransport,
    channel: hostChannel,
    source,
    version
  };

  installCodexDesktop();
  installInputListeners();
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
