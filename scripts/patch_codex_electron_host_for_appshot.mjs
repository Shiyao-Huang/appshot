import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

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

function parseArgs(argv) {
  const options = {
    codexEvidenceRoot: process.env.CODEX_EVIDENCE_ROOT || defaultCodexEvidenceRoot,
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
      "node scripts/patch_codex_electron_host_for_appshot.mjs --output-dir /tmp/codex-appshot-patched --pretty",
      "node scripts/patch_codex_electron_host_for_appshot.mjs --in-place --codex-evidence-root /path/to/codex/mac-app --adapter-path /path/to/codex-host-adapter.cjs"
    ],
    defaultMode: "dry-run",
    note: "This script never mutates Codex.app unless --in-place is passed. --output-dir writes a minimal patched evidence copy under outputDir/asar-522."
  };
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

function targetPaths(options) {
  const sourceRoot = resolve(options.codexEvidenceRoot);
  const sourceAsar = join(sourceRoot, "asar-522");
  const sourceBuild = join(sourceAsar, ".vite", "build");
  const writeRoot = options.inPlace
    ? sourceRoot
    : options.outputDir
      ? resolve(options.outputDir)
      : null;
  const writeAsar = writeRoot ? join(writeRoot, "asar-522") : null;
  const writeBuild = writeAsar ? join(writeAsar, ".vite", "build") : null;
  return {
    sourceRoot,
    sourceAsar,
    sourceBuild,
    sourcePackage: join(sourceAsar, "package.json"),
    sourceMain: join(sourceBuild, "main-DVEWN1ng.js"),
    sourceCommentPreload: join(sourceBuild, "comment-preload.js"),
    sourcePreload: join(sourceBuild, "preload.js"),
    writeRoot,
    writeAsar,
    writeBuild,
    writePackage: writeAsar ? join(writeAsar, "package.json") : null,
    writeMain: writeBuild ? join(writeBuild, "main-DVEWN1ng.js") : null,
    writeCommentPreload: writeBuild ? join(writeBuild, "comment-preload.js") : null,
    writePreload: writeBuild ? join(writeBuild, "preload.js") : null
  };
}

function patchMainBundle(source, adapterPath) {
  const anchors = {
    channelConstants: "var ws=`codex_desktop:message-from-view`,F=`codex_desktop:message-for-view`,Ts=`codex_desktop:browser-sidebar-runtime-message`,",
    handlerRegistration: "n.ipcMain.handle(ws,"
  };
  if (!source.includes(anchors.channelConstants)) {
    throw new Error("main bundle missing Codex IPC channel constants anchor");
  }
  if (!source.includes(anchors.handlerRegistration)) {
    throw new Error("main bundle missing ipcMain.handle registration anchor");
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
  const withHelper = source.replace(anchors.channelConstants, `${anchors.channelConstants}${helper}`);
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
    sourceCodexEvidenceRoot: paths.sourceRoot,
    outputCodexEvidenceRoot: paths.writeRoot,
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
      analyzerCommand: writesEnabled
        ? `CODEX_EVIDENCE_ROOT=${paths.writeRoot} node scripts/analyze_codex_electron_host_injection.mjs`
        : "node scripts/analyze_codex_electron_host_injection.mjs",
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
