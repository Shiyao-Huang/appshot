# AppShot Codex Host Bridge Adapter

This adapter is the Codex-side integration boundary for AppShot's browser runtime bridge.

It does not patch or attach to Codex.app by itself. It is meant to be loaded from a host Electron process that owns Codex-style browser WebContents. Codex 522's browser sidebar uses a guest webview with `comment-preload.js`: `sendMessageToHost` goes from the preload to the main process over `codex_desktop:browser-sidebar-runtime-message` with `ipcRenderer.invoke` / `ipcMain.handle`, while `subscribeToHostMessages` receives host messages over `codex_desktop:message-for-view` with `webContents.send` / `ipcRenderer.on`.

When installed inside that host, this adapter composes `electron-preload/appshot-host-bridge/host.cjs` for AppShot helper compatibility, can tap Codex's `ipcMain.handle` registration when loaded before Codex registers the browser runtime handler, and exposes host-managed browser state for the existing AppShot DOM/runtime payload.

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

For direct Codex-side source edits, wrap the existing runtime handler instead of registering a second handler on the same channel:

```js
ipcMain.handle(
  "codex_desktop:browser-sidebar-runtime-message",
  bridge.wrapCodexRuntimeMessageHandler(async (event, payload) => {
    // existing Codex browser sidebar runtime handler body
  })
);
```

Expected AppShot fields when the matching preload is active:

- `codexBrowserDOMIntegration.browserRuntimeBridge.hostChannel == "codex_desktop:browser-sidebar-runtime-message"`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostOutboundChannel == "codex_desktop:message-for-view"`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostAPI == ["sendMessageToHost", "subscribeToHostMessages"]`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostOwner == "codex-electron-host"`
- `codexBrowserDOMIntegration.browserRuntimeBridge.hostTransport == "codex-electron-ipc+appshot-electron-ipc"`

Run `scripts/analyze_codex_electron_host_injection.mjs` from a source checkout to verify the packaged Codex insertion points without mutating Codex.app. Installed releases also carry this analyzer and `scripts/patch_codex_electron_host_for_appshot.mjs` inside the Codex integration directory, for example `~/.local/share/appshot/codex-integration/appshot-codex-host-bridge/scripts/patch_codex_electron_host_for_appshot.mjs`. The analyzer and patcher discover hashed `main-*.js` bundles from Codex IPC anchors instead of a fixed filename. The patcher's default dry-run mode reports the exact main-bundle and `comment-preload.js` anchors it would patch; pass `--asar-root /path/to/unpacked/app.asar` for a real unpacked Codex asar, or `--codex-app /Applications/Codex.app` to inspect whether the app exposes an unpacked asar. If the app only contains a packed `Contents/Resources/app.asar`, the tools fail with an explicit "extract first" message rather than pretending the private host was patched.

The standalone AppShot CLI/MCP status reports this artifact as installed, but `codexComputerUseStatus.hostBridge.codexHostIntegration.privateCodexWebviewHostAttached` remains `false` until an actual Codex-side Electron host loads the adapter before handler registration or wraps the existing Codex runtime handler.
