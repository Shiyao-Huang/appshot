import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const workspaceRoot = resolve(root, "..");
const defaultCodexEvidenceRoot = join(workspaceRoot, "codex-522", "mac-app");
const defaultAdapterPath = join(
  homedir(),
  ".local",
  "share",
  "appshot",
  "codex-integration",
  "appshot-codex-host-bridge",
  "codex-host-adapter.cjs"
);

const mainMarker = "appshot-codex-host-bridge-main-installed";
const preloadMarker = "appshot-codex-host-bridge-preload-exposed";
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
    adapterPath: process.env.APPSHOT_CODEX_HOST_ADAPTER_PATH || defaultAdapterPath,
    outputDir: null,
    inPlace: false,
    pretty: false
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
      case "--adapter-path":
        options.adapterPath = next();
        break;
      case "--output-dir":
        options.outputDir = next();
        break;
      case "--in-place":
        options.inPlace = true;
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
      "node scripts/patch_codex_electron_host_for_appshot.mjs [--pretty]",
      "node scripts/patch_codex_electron_host_for_appshot.mjs --asar-root /path/to/unpacked/app.asar --output-dir /tmp/codex-appshot-patched --pretty",
      "node scripts/patch_codex_electron_host_for_appshot.mjs --codex-app /Applications/Codex.app --pretty",
      "node scripts/patch_codex_electron_host_for_appshot.mjs --in-place --asar-root /path/to/unpacked/app.asar --adapter-path /path/to/codex-host-adapter.cjs"
    ],
    defaultMode: "dry-run",
    note: "This script never mutates Codex.app unless --in-place is passed. It patches unpacked asar directories; packed app.asar files must be extracted first."
  };
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
    throw new Error(`Missing required file: ${path}`);
  }
  return readFileSync(path, "utf8");
}

function ensureParent(path) {
  mkdirSync(dirname(path), { recursive: true });
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
      throw new Error(`--asar-root must point to an unpacked Codex asar directory with package.json and ${buildRelativePath}: ${sourceAsar}`);
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
      throw new Error(`Codex app uses packed app.asar at ${packedAsar}. Extract it first, then pass the extracted directory with --asar-root; this patcher does not pretend to patch packed archives.`);
    }
    throw new Error(`Could not find an unpacked Codex asar directory inside ${codexApp}`);
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
    throw new Error(`Could not find an unpacked Codex asar under ${sourceRoot}`);
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
    throw new Error(`Could not find a Codex Electron main bundle with browser-sidebar-runtime-message anchors under ${buildRoot}`);
  }
  return candidates[0];
}

function targetPaths(options) {
  const layout = resolveSourceLayout(options);
  const sourceBuild = join(layout.sourceAsar, buildRelativePath);
  const sourceMainBundle = discoverMainBundle(sourceBuild);
  let writeRoot = null;
  let writeAsar = null;
  if (options.inPlace) {
    writeRoot = layout.sourceRoot;
    writeAsar = layout.sourceAsar;
  } else if (options.outputDir) {
    writeRoot = resolve(options.outputDir);
    writeAsar = join(writeRoot, basename(layout.sourceAsar));
  }
  const writeBuild = writeAsar ? join(writeAsar, buildRelativePath) : null;
  return {
    ...layout,
    sourceBuild,
    sourceMainBundle: sourceMainBundle.name,
    sourcePackage: join(layout.sourceAsar, "package.json"),
    sourceMain: sourceMainBundle.path,
    sourceCommentPreload: join(sourceBuild, "comment-preload.js"),
    sourcePreload: join(sourceBuild, "preload.js"),
    writeRoot,
    writeAsar,
    writeBuild,
    writePackage: writeAsar ? join(writeAsar, "package.json") : null,
    writeMain: writeBuild ? join(writeBuild, sourceMainBundle.name) : null,
    writeCommentPreload: writeBuild ? join(writeBuild, "comment-preload.js") : null,
    writePreload: writeBuild ? join(writeBuild, "preload.js") : null
  };
}

function patchMainBundle(source, adapterPath) {
  const anchors = {
    channelConstants: "var ws=`codex_desktop:message-from-view`,F=`codex_desktop:message-for-view`,Ts=`codex_desktop:browser-sidebar-runtime-message`,",
    helperInsertion: "Vs=`codex_desktop`;function Hs",
    handlerRegistration: "n.ipcMain.handle(Ts,"
  };
  if (!source.includes(anchors.channelConstants)) {
    throw new Error("main bundle missing Codex IPC channel constants anchor");
  }
  if (!source.includes(anchors.helperInsertion)) {
    throw new Error("main bundle missing Codex IPC constants terminator anchor");
  }
  if (!source.includes(anchors.handlerRegistration)) {
    throw new Error("main bundle missing browser runtime ipcMain.handle registration anchor");
  }
  if (source.includes(mainMarker)) {
    return {
      text: source,
      changed: false,
      anchors
    };
  }

  const helper = [
    `var __appshotCodexHostBridge=null;`,
    `function __appshotInstallCodexHostBridge(e,n){`,
    `if(__appshotCodexHostBridge)return __appshotCodexHostBridge;`,
    `try{`,
    `let r=process.env.APPSHOT_CODEX_HOST_ADAPTER_PATH||${JSON.stringify(adapterPath)};`,
    `let i=require(r);`,
    `__appshotCodexHostBridge=i.installAppShotCodexHostBridge(e,{getBrowserState:e=>e||{}});`,
    `return __appshotCodexHostBridge`,
    `}catch(e){try{n.$r().warning(\`${mainMarker}\`,{safe:{},sensitive:{error:e}})}catch{}`,
    `return null}`,
    `}`
  ].join("");
  const withHelper = source.replace(anchors.helperInsertion, `Vs=\`codex_desktop\`;${helper}function Hs`);
  const call = `__appshotInstallCodexHostBridge(n.ipcMain,t),`;
  return {
    text: withHelper.replace(anchors.handlerRegistration, `${call}${anchors.handlerRegistration}`),
    changed: true,
    anchors
  };
}

function patchCommentPreload(source) {
  const anchors = {
    channelConstants: "var Oe=`codex_desktop:message-for-view`,ke=`codex_desktop:browser-sidebar-runtime-message`;",
    bridgeFactory: "function $f(){return{initialState:Vf,",
    sourceMap: "\n//# sourceMappingURL=comment-preload.js.map"
  };
  for (const [name, needle] of Object.entries(anchors)) {
    if (!source.includes(needle)) {
      throw new Error(`comment preload missing ${name} anchor`);
    }
  }
  if (source.includes(preloadMarker)) {
    return {
      text: source,
      changed: false,
      anchors
    };
  }

  const exposure = [
    `;(()=>{try{`,
    `let e=$f();`,
    `e.__appshotHostOwner="codex-electron-host";`,
    `e.__appshotHostTransport="codex-electron-ipc+appshot-electron-ipc";`,
    `e.__appshotHostInboundChannel="codex_desktop:browser-sidebar-runtime-message";`,
    `e.__appshotHostOutboundChannel="codex_desktop:message-for-view";`,
    `e.__appshotIPCPattern="ipcRenderer.invoke/ipcMain.handle + webContents.send/ipcRenderer.on";`,
    `let t={available:!0,codexHostBridgeAvailable:!0,owner:"codex-electron-host",transport:"codex-electron-ipc+appshot-electron-ipc",channel:"codex_desktop:browser-sidebar-runtime-message",outboundChannel:"codex_desktop:message-for-view",hostOutboundChannel:"codex_desktop:message-for-view",hostAPI:["sendMessageToHost","subscribeToHostMessages"],ipcPattern:"ipcRenderer.invoke/ipcMain.handle + webContents.send/ipcRenderer.on",source:"${preloadMarker}"};`,
    `globalThis.__appshotRuntimeBridgeInstalled=!0;`,
    `globalThis.__appshotBrowserBridgeHost=t;`,
    `if(d.contextBridge&&typeof d.contextBridge.exposeInMainWorld==="function"){`,
    `d.contextBridge.exposeInMainWorld("codex_desktop",e);`,
    `d.contextBridge.exposeInMainWorld("__appshotBrowserBridgeHost",t)`,
    `}else{globalThis.codex_desktop=e}`,
    `}catch(e){}})();`
  ].join("");
  return {
    text: source.replace(anchors.sourceMap, `${exposure}${anchors.sourceMap}`),
    changed: true,
    anchors
  };
}

function writeCopyInputs(paths) {
  if (!paths.writeRoot) {
    return;
  }
  for (const [from, to] of [
    [paths.sourcePackage, paths.writePackage],
    [paths.sourcePreload, paths.writePreload]
  ]) {
    ensureParent(to);
    copyFileSync(from, to);
  }
}

function analyzerCommandFor(paths) {
  const analyzer = "node scripts/analyze_codex_electron_host_injection.mjs";
  if (paths.writeAsar) {
    return `${analyzer} --asar-root ${JSON.stringify(paths.writeAsar)}`;
  }
  return `${analyzer} --asar-root ${JSON.stringify(paths.sourceAsar)}`;
}

function run(options) {
  if (options.help) {
    return usage();
  }
  if (options.inPlace && options.outputDir) {
    throw new Error("Use either --in-place or --output-dir, not both.");
  }
  const paths = targetPaths(options);
  const mainSource = readRequired(paths.sourceMain);
  const commentPreloadSource = readRequired(paths.sourceCommentPreload);
  readRequired(paths.sourcePackage);
  readRequired(paths.sourcePreload);

  const mainPatch = patchMainBundle(mainSource, resolve(options.adapterPath));
  const preloadPatch = patchCommentPreload(commentPreloadSource);
  const writesEnabled = Boolean(paths.writeRoot);

  if (writesEnabled) {
    writeCopyInputs(paths);
    ensureParent(paths.writeMain);
    ensureParent(paths.writeCommentPreload);
    writeFileSync(paths.writeMain, mainPatch.text);
    writeFileSync(paths.writeCommentPreload, preloadPatch.text);
  }

  return {
    format: "appshot-codex-electron-host-patch-plan",
    source: "patch_codex_electron_host_for_appshot",
    mode: options.inPlace ? "in-place" : options.outputDir ? "copy" : "dry-run",
    sourceKind: paths.sourceKind,
    sourceCodexEvidenceRoot: paths.sourceRoot,
    sourceCodexApp: paths.codexApp,
    sourceAsarRoot: paths.sourceAsar,
    sourceMainBundle: paths.sourceMainBundle,
    outputCodexEvidenceRoot: paths.writeRoot,
    outputAsarRoot: paths.writeAsar,
    adapterPath: resolve(options.adapterPath),
    markers: {
      main: mainMarker,
      preload: preloadMarker
    },
    changed: {
      main: mainPatch.changed,
      commentPreload: preloadPatch.changed
    },
    patchedFiles: writesEnabled ? {
      package: paths.writePackage,
      preload: paths.writePreload,
      main: paths.writeMain,
      commentPreload: paths.writeCommentPreload
    } : {},
    anchors: {
      main: mainPatch.anchors,
      commentPreload: preloadPatch.anchors
    },
    verification: {
      analyzerCommand: analyzerCommandFor(paths),
      privateHostStillRequiresLaunchingPatchedCodex: true
    }
  };
}

try {
  const options = parseArgs(process.argv.slice(2));
  const payload = run(options);
  process.stdout.write(`${JSON.stringify(payload, null, options.pretty ? 2 : 0)}\n`);
} catch (error) {
  process.stderr.write(`appshot codex host patcher: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
}
