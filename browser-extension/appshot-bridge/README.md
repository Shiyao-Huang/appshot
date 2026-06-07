# AppShot Browser Bridge Extension

This unpacked MV3 helper is the public, browser-owned bridge toward Codex's embedded comment preload model.

It installs `page-bridge.js` in the page main world, exposes `window.codex_desktop.sendMessageToHost` and `window.codex_desktop.subscribeToHostMessages`, relays page messages through an isolated content script, and keeps a background service-worker event log keyed by tab/frame.

The helper intentionally does not claim Codex's private Electron host IPC. It gives AppShot a real browser extension/preload helper with its own `window.postMessage + extension runtime` transport, so `--include-browser-dom` can detect:

- `codexBrowserDOMIntegration.browserRuntimeBridge.extensionHelperAvailable`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostOwner == "browser-extension"`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostTransport == "window.postMessage+extension-runtime"`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostChannel == "codex_desktop:browser-sidebar-runtime-message"`

For local development, load this directory as an unpacked extension in a Chromium-style browser, then capture the active tab with:

```sh
appshot capture --include-browser-dom --pretty
```
