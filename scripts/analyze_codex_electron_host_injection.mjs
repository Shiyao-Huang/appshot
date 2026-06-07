import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const workspaceRoot = resolve(root, "..");
const codexEvidenceRoot = resolve(process.env.CODEX_EVIDENCE_ROOT || join(workspaceRoot, "codex-522", "mac-app"));
const asarRoot = join(codexEvidenceRoot, "asar-522");
const buildRoot = join(asarRoot, ".vite", "build");
const packagePath = join(asarRoot, "package.json");
const mainPath = join(buildRoot, "main-DVEWN1ng.js");
const commentPreloadPath = join(buildRoot, "comment-preload.js");
const preloadPath = join(buildRoot, "preload.js");

function fail(message) {
  throw new Error(message);
}

function readRequired(path) {
  if (!existsSync(path)) {
    fail(`missing required Codex evidence: ${path}`);
  }
  return readFileSync(path, "utf8");
}

function anchor(text, file, name, needle) {
  const position = text.indexOf(needle);
  if (position < 0) {
    fail(`${file} missing ${name}: ${needle}`);
  }
  return { file, name, needle, position };
}

function maybeJSON(text) {
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

const main = readRequired(mainPath);
const commentPreload = readRequired(commentPreloadPath);
const preload = readRequired(preloadPath);
const packageJSON = maybeJSON(readRequired(packagePath));

const mainAnchors = [
  anchor(main, "main-DVEWN1ng.js", "main view preload path", "preload:this.options.preloadPath"),
  anchor(main, "main-DVEWN1ng.js", "primary BrowserWindow webview tag", "webviewTag:!0"),
  anchor(main, "main-DVEWN1ng.js", "browser sidebar preload path", "qk=(0,i.join)(__dirname,`comment-preload.js`)"),
  anchor(main, "main-DVEWN1ng.js", "browser sidebar will-attach-webview hook", "n.on(`will-attach-webview`,o)"),
  anchor(main, "main-DVEWN1ng.js", "browser sidebar did-attach-webview hook", "n.on(`did-attach-webview`,s)"),
  anchor(main, "main-DVEWN1ng.js", "browser sidebar webview preload assignment", "i.preload=qk"),
  anchor(main, "main-DVEWN1ng.js", "browser sidebar page attach", "this.attachPageWebContents(a,o.page,t,o.themeVariant)"),
  anchor(main, "main-DVEWN1ng.js", "Codex runtime IPC handler", "n.ipcMain.handle(Ts,"),
  anchor(main, "main-DVEWN1ng.js", "Codex host-to-view runtime sync", "t.send(F,{type:`browser-sidebar-runtime-sync`")
];

const commentPreloadAnchors = [
  anchor(commentPreload, "comment-preload.js", "host-to-view channel constant", "Oe=`codex_desktop:message-for-view`"),
  anchor(commentPreload, "comment-preload.js", "view-to-host channel constant", "ke=`codex_desktop:browser-sidebar-runtime-message`"),
  anchor(commentPreload, "comment-preload.js", "sendMessageToHost invoke", "sendMessageToHost(e){d.ipcRenderer.invoke(ke,e)}"),
  anchor(commentPreload, "comment-preload.js", "subscribeToHostMessages", "subscribeToHostMessages(e){Hf=!0"),
  anchor(commentPreload, "comment-preload.js", "host-to-view subscription", "d.ipcRenderer.on(Oe,t)"),
  anchor(commentPreload, "comment-preload.js", "unsubscribed host-to-view listener", "d.ipcRenderer.on(Oe,(e,t)=>")
];

const preloadAnchors = [
  anchor(preload, "preload.js", "main view message-from-view", "codex_desktop:message-from-view"),
  anchor(preload, "preload.js", "main view message-for-view", "codex_desktop:message-for-view"),
  anchor(preload, "preload.js", "main electronBridge exposure", "exposeInMainWorld(`electronBridge`,w)")
];

const analysis = {
  format: "codex-electron-host-injection-analysis",
  source: "appshot-codex-522-packaged-electron-analysis",
  codexEvidenceRoot,
  package: {
    name: packageJSON.name || "",
    version: packageJSON.version || "",
    main: packageJSON.main || ""
  },
  channels: {
    hostInboundChannel: "codex_desktop:browser-sidebar-runtime-message",
    hostOutboundChannel: "codex_desktop:message-for-view",
    mainViewInboundChannel: "codex_desktop:message-from-view",
    mainViewOutboundChannel: "codex_desktop:message-for-view",
    viewToHostPattern: "comment-preload sendMessageToHost -> ipcRenderer.invoke(ke, payload)",
    hostRuntimeHandlerPattern: "main n.ipcMain.handle(Ts, async(event, payload) => ...)",
    hostToViewPattern: "main webContents.send(F, payload) -> comment-preload ipcRenderer.on(Oe, listener)"
  },
  preloadLifecycle: {
    primaryWindowUsesMainPreload: true,
    primaryWindowEnablesWebviewTag: true,
    browserSidebarUsesGuestWebview: true,
    browserSidebarPreloadPathExpression: "qk=(0,i.join)(__dirname,`comment-preload.js`)",
    willAttachWebviewSetsCommentPreload: true,
    didAttachWebviewRecordsGuestWebContents: true,
    mainWindowPreloadIsNotTheBrowserSidebarPreload: true
  },
  injectionPoints: [
    {
      id: "load-adapter-before-codex-runtime-handler-registration",
      file: "main-DVEWN1ng.js",
      anchor: "n.ipcMain.handle(Ts,",
      action: "Load codex-host-adapter.cjs before the Codex browser runtime handler is registered so it can wrap ipcMain.handle for the inbound runtime channel."
    },
    {
      id: "manual-wrap-codex-runtime-handler",
      file: "main-DVEWN1ng.js",
      anchor: "n.ipcMain.handle(Ts, async(e,r)=>...)",
      action: "Replace the handler argument with bridge.wrapCodexRuntimeMessageHandler(originalHandler) when editing Codex-side source directly."
    },
    {
      id: "send-host-state-to-comment-preload",
      file: "main-DVEWN1ng.js",
      anchor: "t.send(F,{type:`browser-sidebar-runtime-sync`",
      action: "Use bridge.sendCodexHostState(webContents, state) or webContents.send('codex_desktop:message-for-view', runtimeEvent) for host-to-view updates."
    },
    {
      id: "browser-sidebar-guest-preload-lifecycle",
      file: "main-DVEWN1ng.js",
      anchor: "i.preload=qk",
      action: "Treat comment-preload.js as the browser sidebar guest preload; the main BrowserWindow preload.js is not enough for AppShot browser runtime parity."
    }
  ],
  anchors: {
    main: mainAnchors,
    commentPreload: commentPreloadAnchors,
    preload: preloadAnchors
  },
  remainingNonClaim: "This analysis proves the Codex 522 packaged insertion points and IPC direction. It does not mutate Codex.app or prove a live private Codex webview host is attached."
};

process.stdout.write(`${JSON.stringify(analysis, null, 2)}\n`);
