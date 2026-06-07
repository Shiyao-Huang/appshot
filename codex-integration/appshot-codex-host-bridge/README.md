# AppShot Codex Host Bridge Adapter

This adapter is the Codex-side integration boundary for AppShot's browser runtime bridge.

It does not patch or attach to Codex.app by itself. It is meant to be loaded from a host Electron process that owns Codex-style browser WebContents. When installed inside that host, it composes `electron-preload/appshot-host-bridge/host.cjs`, listens on `codex_desktop:browser-sidebar-runtime-message`, and exposes host-managed browser state for the existing AppShot DOM/runtime payload.

```js
const { ipcMain } = require("electron");
const {
  installAppShotCodexHostBridge
} = require("~/.local/share/appshot/codex-integration/appshot-codex-host-bridge/codex-host-adapter.cjs");

const bridge = installAppShotCodexHostBridge(ipcMain, {
  getBrowserState() {
    return {
      interactionMode: "comment",
      annotationEditorMode: "comment",
      isOriginalViewEnabled: false,
      isDesignModifierPressed: false
    };
  },
  onCodexRuntimeMessage(payload, event, state) {
    console.log("AppShot Codex runtime message", payload, state.eventCount);
  }
});
```

Expected AppShot fields when the matching preload is active:

- `codexBrowserDOMIntegration.browserRuntimeBridge.hostChannel == "codex_desktop:browser-sidebar-runtime-message"`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostAPI == ["sendMessageToHost", "subscribeToHostMessages"]`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostOwner == "codex-electron-host"`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostTransport == "codex-electron-ipc+appshot-electron-ipc"`

The standalone AppShot CLI/MCP status reports this artifact as installed, but `codexComputerUseStatus.hostBridge.codexHostIntegration.privateCodexWebviewHostAttached` remains `false` until an actual Codex-side Electron host loads the adapter.
