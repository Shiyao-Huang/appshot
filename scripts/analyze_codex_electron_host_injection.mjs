import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const workspaceRoot = resolve(root, "..");
const defaultCodexEvidenceRoot = join(workspaceRoot, "codex-522", "mac-app");
const buildRelativePath = join(".vite", "build");
const unpackedAsarAppCandidates = [
  join("Contents", "Resources", "app"),
  join("Contents", "Resources", "app.asar.unpacked"),
  join("Contents", "Resources", "app.asar.extracted")
];

function parseArgs(argv) {
  const options = {
    codexEvidenceRoot: process.env.CODEX_EVIDENCE_ROOT || defaultCodexEvidenceRoot,
    asarRoot: process.env.CODEX_ASAR_ROOT || null,
    codexApp: process.env.CODEX_APP_PATH || null,
    pretty: true
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) {
        throw new Error(`Missing value for ${arg}`);
      }
      return argv[index];
    };
    switch (arg) {
      case "--codex-evidence-root":
        options.codexEvidenceRoot = next();
        break;
      case "--asar-root":
        options.asarRoot = next();
        break;
      case "--codex-app":
        options.codexApp = next();
        break;
      case "--compact":
        options.pretty = false;
        break;
      case "--pretty":
        options.pretty = true;
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }
  return options;
}

function usage() {
  return {
    usage: [
      "node scripts/analyze_codex_electron_host_injection.mjs",
      "node scripts/analyze_codex_electron_host_injection.mjs --asar-root /path/to/unpacked/app.asar",
      "node scripts/analyze_codex_electron_host_injection.mjs --codex-app /Applications/Codex.app"
    ],
    note: "Analyzes unpacked Codex asar directories. Packed app.asar files must be extracted before analysis."
  };
}

function fail(message) {
  throw new Error(message);
}

function statMaybe(path) {
  try {
    return statSync(path);
  } catch {
    return null;
  }
}

function isDirectory(path) {
  return statMaybe(path)?.isDirectory() === true;
}

function isFile(path) {
  return statMaybe(path)?.isFile() === true;
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

function anchorPattern(text, file, name, pattern, description) {
  const match = pattern.exec(text);
  if (!match || match.index < 0) {
    fail(`${file} missing ${name}: ${description}`);
  }
  return { file, name, needle: description, position: match.index, match: match[0] };
}

function maybeJSON(text) {
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

function hasUnpackedAsarShape(path) {
  return isFile(join(path, "package.json")) && isDirectory(join(path, buildRelativePath));
}

function discoverAsarRootInEvidenceRoot(sourceRoot) {
  const preferred = join(sourceRoot, "asar-522");
  if (hasUnpackedAsarShape(preferred)) {
    return preferred;
  }
  if (!isDirectory(sourceRoot)) {
    return null;
  }
  return readdirSync(sourceRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && /^asar(?:-|$)/.test(entry.name))
    .map((entry) => join(sourceRoot, entry.name))
    .find(hasUnpackedAsarShape) ?? null;
}

function resolveSourceLayout(options) {
  if (options.asarRoot) {
    const sourceAsar = resolve(options.asarRoot);
    if (!hasUnpackedAsarShape(sourceAsar)) {
      fail(`--asar-root must point to an unpacked Codex asar directory with package.json and ${buildRelativePath}: ${sourceAsar}`);
    }
    return {
      sourceKind: "asar-root",
      sourceRoot: dirname(sourceAsar),
      sourceAsar,
      codexApp: null
    };
  }

  if (options.codexApp) {
    const codexApp = resolve(options.codexApp);
    for (const relative of unpackedAsarAppCandidates) {
      const candidate = join(codexApp, relative);
      if (hasUnpackedAsarShape(candidate)) {
        return {
          sourceKind: "codex-app-unpacked-asar",
          sourceRoot: codexApp,
          sourceAsar: candidate,
          codexApp
        };
      }
    }
    const packedAsar = join(codexApp, "Contents", "Resources", "app.asar");
    if (isFile(packedAsar)) {
      fail(`Codex app uses packed app.asar at ${packedAsar}. Extract it first, then pass the extracted directory with --asar-root; this analyzer does not pretend to inspect files inside packed archives.`);
    }
    fail(`Could not find an unpacked Codex asar directory inside ${codexApp}`);
  }

  const sourceRoot = resolve(options.codexEvidenceRoot);
  if (hasUnpackedAsarShape(sourceRoot)) {
    return {
      sourceKind: "asar-root",
      sourceRoot: dirname(sourceRoot),
      sourceAsar: sourceRoot,
      codexApp: null
    };
  }
  const sourceAsar = discoverAsarRootInEvidenceRoot(sourceRoot);
  if (!sourceAsar) {
    fail(`Could not find an unpacked Codex asar under ${sourceRoot}`);
  }
  return {
    sourceKind: "codex-evidence-root",
    sourceRoot,
    sourceAsar,
    codexApp: null
  };
}

function discoverMainBundle(buildRoot) {
  const names = readdirSync(buildRoot)
    .filter((name) => /^main-.*\.js$/.test(name))
    .sort((a, b) => a.localeCompare(b));
  const candidates = [];
  for (const name of names) {
    const path = join(buildRoot, name);
    const text = readFileSync(path, "utf8");
    if (
      text.includes("codex_desktop:browser-sidebar-runtime-message") &&
      text.includes("codex_desktop:message-for-view") &&
      text.includes("comment-preload.js") &&
      text.includes("n.ipcMain.handle(Ts,")
    ) {
      candidates.push({ name, path });
    }
  }
  if (candidates.length === 0) {
    fail(`Could not find a Codex Electron main bundle with browser-sidebar-runtime-message anchors under ${buildRoot}`);
  }
  return candidates[0];
}

function run(options) {
  if (options.help) {
    return usage();
  }

  const layout = resolveSourceLayout(options);
  const buildRoot = join(layout.sourceAsar, buildRelativePath);
  const packagePath = join(layout.sourceAsar, "package.json");
  const mainBundle = discoverMainBundle(buildRoot);
  const mainPath = mainBundle.path;
  const commentPreloadPath = join(buildRoot, "comment-preload.js");
  const preloadPath = join(buildRoot, "preload.js");

  const main = readRequired(mainPath);
  const commentPreload = readRequired(commentPreloadPath);
  const preload = readRequired(preloadPath);
  const packageJSON = maybeJSON(readRequired(packagePath));

  const mainFile = basename(mainPath);
  const mainAnchors = [
    anchor(main, mainFile, "main view preload path", "preload:this.options.preloadPath"),
    anchor(main, mainFile, "primary BrowserWindow webview tag", "webviewTag:!0"),
    anchor(main, mainFile, "browser sidebar preload path", "comment-preload.js"),
    anchor(main, mainFile, "browser sidebar will-attach-webview hook", "n.on(`will-attach-webview`,o)"),
    anchor(main, mainFile, "browser sidebar did-attach-webview hook", "n.on(`did-attach-webview`,s)"),
    anchorPattern(main, mainFile, "browser sidebar webview preload assignment", /[A-Za-z_$][\w$]*\.preload=[A-Za-z_$][\w$]*/, "webview options preload assignment"),
    anchor(main, mainFile, "browser sidebar page attach", "this.attachPageWebContents(a,o.page,t,o.themeVariant)"),
    anchor(main, mainFile, "Codex runtime IPC handler", "n.ipcMain.handle(Ts,"),
    anchor(main, mainFile, "Codex host-to-view runtime sync", "t.send(F,{type:`browser-sidebar-runtime-sync`")
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

  return {
    format: "codex-electron-host-injection-analysis",
    source: "appshot-codex-packaged-electron-analysis",
    sourceKind: layout.sourceKind,
    codexEvidenceRoot: layout.sourceKind === "codex-evidence-root" ? layout.sourceRoot : null,
    codexApp: layout.codexApp,
    asarRoot: layout.sourceAsar,
    package: {
      name: packageJSON.name || "",
      version: packageJSON.version || "",
      main: packageJSON.main || ""
    },
    files: {
      main: mainPath,
      mainBundle: mainBundle.name,
      commentPreload: commentPreloadPath,
      preload: preloadPath
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
      browserSidebarPreloadPathExpression: "join(__dirname, `comment-preload.js`)",
      willAttachWebviewSetsCommentPreload: true,
      didAttachWebviewRecordsGuestWebContents: true,
      mainWindowPreloadIsNotTheBrowserSidebarPreload: true
    },
    injectionPoints: [
      {
        id: "load-adapter-before-codex-runtime-handler-registration",
        file: mainBundle.name,
        anchor: "n.ipcMain.handle(Ts,",
        action: "Load codex-host-adapter.cjs before the Codex browser runtime handler is registered so it can wrap ipcMain.handle for the inbound runtime channel."
      },
      {
        id: "manual-wrap-codex-runtime-handler",
        file: mainBundle.name,
        anchor: "n.ipcMain.handle(Ts, async(e,r)=>...)",
        action: "Replace the handler argument with bridge.wrapCodexRuntimeMessageHandler(originalHandler) when editing Codex-side source directly."
      },
      {
        id: "send-host-state-to-comment-preload",
        file: mainBundle.name,
        anchor: "t.send(F,{type:`browser-sidebar-runtime-sync`",
        action: "Use bridge.sendCodexHostState(webContents, state) or webContents.send('codex_desktop:message-for-view', runtimeEvent) for host-to-view updates."
      },
      {
        id: "browser-sidebar-guest-preload-lifecycle",
        file: mainBundle.name,
        anchor: "webview options preload assignment",
        action: "Treat comment-preload.js as the browser sidebar guest preload; the main BrowserWindow preload.js is not enough for AppShot browser runtime parity."
      }
    ],
    anchors: {
      main: mainAnchors,
      commentPreload: commentPreloadAnchors,
      preload: preloadAnchors
    },
    remainingNonClaim: "This analysis proves packaged Codex insertion points and IPC direction for an unpacked asar. It does not mutate Codex.app or prove a live private Codex webview host is attached."
  };
}

try {
  const options = parseArgs(process.argv.slice(2));
  const payload = run(options);
  process.stdout.write(`${JSON.stringify(payload, null, options.pretty ? 2 : 0)}\n`);
} catch (error) {
  process.stderr.write(`appshot codex host analyzer: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
}
