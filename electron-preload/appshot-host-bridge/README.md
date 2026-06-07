# AppShot Electron Host Bridge

This optional helper is for Electron hosts that can choose their own preload script. It is the AppShot-owned step closest to Codex's embedded browser preload shape:

- `preload.cjs` exposes `window.codex_desktop.sendMessageToHost`
- `preload.cjs` exposes `window.codex_desktop.subscribeToHostMessages`
- `host.cjs` registers `ipcMain` on `codex_desktop:browser-sidebar-runtime-message`
- AppShot DOM captures can detect `hostOwner: electron-preload` and `hostTransport: electron-ipc`

Example Electron main-process wiring:

```js
const path = require("node:path");
const { BrowserWindow, ipcMain } = require("electron");
const { installAppShotElectronHostBridge } = require("./host.cjs");

const bridge = installAppShotElectronHostBridge(ipcMain);
const win = new BrowserWindow({
  webPreferences: {
    preload: path.join(__dirname, "preload.cjs"),
    contextIsolation: true,
    nodeIntegration: false
  }
});

bridge.sendToWebContents(win.webContents, {
  message: { type: "browser-sidebar-runtime-sync" }
});
```

This helper does not claim Codex's private Electron webview host bridge. It gives Electron apps an AppShot-provided host/preload channel with the same public page API names and runtime event channel shape.
