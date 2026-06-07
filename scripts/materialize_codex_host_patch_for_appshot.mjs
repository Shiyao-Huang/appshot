import { spawnSync } from "node:child_process";
import {
  chmodSync,
  closeSync,
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  readSync,
  readdirSync,
  rmSync,
  statSync,
  writeSync
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const defaultCodexApp = "/Applications/Codex.app";
const defaultAdapterPath = join(
  homedir(),
  ".local",
  "share",
  "appshot",
  "codex-integration",
  "appshot-codex-host-bridge",
  "codex-host-adapter.cjs"
);
const patcherPath = join(root, "scripts", "patch_codex_electron_host_for_appshot.mjs");
const analyzerPath = join(root, "scripts", "analyze_codex_electron_host_injection.mjs");

function parseArgs(argv) {
  const options = {
    codexApp: process.env.CODEX_APP_PATH || defaultCodexApp,
    asarRoot: process.env.CODEX_ASAR_ROOT || null,
    adapterPath: process.env.APPSHOT_CODEX_HOST_ADAPTER_PATH || defaultAdapterPath,
    outputDir: null,
    copyAppBundle: false,
    force: false,
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
      case "--codex-app":
        options.codexApp = next();
        break;
      case "--asar-root":
        options.asarRoot = next();
        break;
      case "--adapter-path":
        options.adapterPath = next();
        break;
      case "--output-dir":
        options.outputDir = next();
        break;
      case "--copy-app-bundle":
        options.copyAppBundle = true;
        break;
      case "--force":
        options.force = true;
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
      "node scripts/materialize_codex_host_patch_for_appshot.mjs --codex-app /Applications/Codex.app --output-dir /tmp/codex-appshot-host --pretty",
      "node scripts/materialize_codex_host_patch_for_appshot.mjs --codex-app /Applications/Codex.app --output-dir /tmp/codex-appshot-host --copy-app-bundle --pretty",
      "node scripts/materialize_codex_host_patch_for_appshot.mjs --asar-root /path/to/unpacked/app.asar --output-dir /tmp/codex-appshot-host --pretty"
    ],
    defaultMode: "extract packed app.asar when needed, patch an unpacked copy, and leave the original Codex.app untouched",
    note: "Use --copy-app-bundle only when you want a runnable copied app bundle. The copied app may require local ad-hoc signing depending on macOS policy."
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

function ensureEmptyOutputDir(outputDir, force) {
  if (existsSync(outputDir)) {
    if (!force && readdirSync(outputDir).length > 0) {
      throw new Error(`Output directory already exists and is not empty: ${outputDir}. Pass --force to replace it.`);
    }
    if (force) {
      rmSync(outputDir, { recursive: true, force: true });
    }
  }
  mkdirSync(outputDir, { recursive: true });
}

function ensureInside(rootPath, relativePath) {
  if (relativePath.startsWith("/") || relativePath.split(/[\\/]/).includes("..")) {
    throw new Error(`Unsafe asar path: ${relativePath}`);
  }
  const target = resolve(rootPath, relativePath);
  const normalizedRoot = resolve(rootPath);
  if (target !== normalizedRoot && !target.startsWith(`${normalizedRoot}${sep}`)) {
    throw new Error(`Unsafe output path: ${target}`);
  }
  return target;
}

function mkdirForFile(path) {
  mkdirSync(dirname(path), { recursive: true });
}

function readAsarHeader(asarPath) {
  const fd = openSync(asarPath, "r");
  try {
    const prefix = Buffer.alloc(16);
    readSync(fd, prefix, 0, prefix.length, 0);
    const headerSizeBytes = prefix.readUInt32LE(0);
    const pickleSize = prefix.readUInt32LE(4);
    const headerSize = prefix.readUInt32LE(8);
    const headerStringSize = prefix.readUInt32LE(12);
    if (headerSizeBytes !== 4 || headerStringSize <= 0 || headerStringSize > headerSize) {
      throw new Error(`Unsupported asar header in ${asarPath}`);
    }
    const headerBuffer = Buffer.alloc(headerStringSize);
    readSync(fd, headerBuffer, 0, headerStringSize, 16);
    const padding = (4 - (headerStringSize % 4)) % 4;
    return {
      header: JSON.parse(headerBuffer.toString("utf8")),
      headerSizeBytes,
      pickleSize,
      headerSize,
      headerStringSize,
      dataOffset: 16 + headerStringSize + padding
    };
  } finally {
    closeSync(fd);
  }
}

function walkAsarFiles(node, prefix = []) {
  if (node.files) {
    const entries = [];
    for (const [name, child] of Object.entries(node.files)) {
      entries.push(...walkAsarFiles(child, [...prefix, name]));
    }
    return entries;
  }
  return [{
    relativePath: prefix.join("/"),
    node
  }];
}

function copyArchiveSlice(archivePath, start, size, outputPath) {
  mkdirForFile(outputPath);
  const input = openSync(archivePath, "r");
  const output = openSync(outputPath, "w");
  try {
    const chunk = Buffer.allocUnsafe(1024 * 1024);
    let remaining = size;
    let position = start;
    while (remaining > 0) {
      const requested = Math.min(chunk.length, remaining);
      const read = readSync(input, chunk, 0, requested, position);
      if (read <= 0) {
        throw new Error(`Unexpected end of asar while extracting ${outputPath}`);
      }
      writeSync(output, chunk, 0, read);
      position += read;
      remaining -= read;
    }
  } finally {
    closeSync(input);
    closeSync(output);
  }
}

function extractPackedAsar({ asarPath, unpackedRoot, outputDir }) {
  const metadata = readAsarHeader(asarPath);
  const files = walkAsarFiles(metadata.header);
  let archiveFileCount = 0;
  let unpackedFileCount = 0;
  let byteCount = 0;

  for (const entry of files) {
    const outputPath = ensureInside(outputDir, entry.relativePath);
    const size = Number(entry.node.size || 0);
    if (entry.node.unpacked) {
      const sourcePath = join(unpackedRoot, ...entry.relativePath.split("/"));
      if (!isFile(sourcePath)) {
        throw new Error(`Missing unpacked asar sidecar file: ${sourcePath}`);
      }
      mkdirForFile(outputPath);
      copyFileSync(sourcePath, outputPath);
      unpackedFileCount += 1;
    } else {
      if (entry.node.offset == null) {
        throw new Error(`Asar file has no offset: ${entry.relativePath}`);
      }
      copyArchiveSlice(asarPath, metadata.dataOffset + Number(entry.node.offset), size, outputPath);
      archiveFileCount += 1;
    }
    if (entry.node.executable) {
      chmodSync(outputPath, 0o755);
    }
    byteCount += size;
  }

  return {
    format: "appshot-asar-extraction",
    asarPath,
    unpackedRoot,
    outputDir,
    dataOffset: metadata.dataOffset,
    headerStringSize: metadata.headerStringSize,
    fileCount: files.length,
    archiveFileCount,
    unpackedFileCount,
    byteCount
  };
}

function hasUnpackedAsarShape(path) {
  return isFile(join(path, "package.json")) && isDirectory(join(path, ".vite", "build"));
}

function resolveSource(options, outputDir) {
  if (options.asarRoot) {
    const sourceAsarRoot = resolve(options.asarRoot);
    if (!hasUnpackedAsarShape(sourceAsarRoot)) {
      throw new Error(`--asar-root must point to an unpacked Codex asar directory: ${sourceAsarRoot}`);
    }
    const extractedAsarRoot = join(outputDir, "app.asar.extracted");
    cpSync(sourceAsarRoot, extractedAsarRoot, { recursive: true });
    return {
      sourceKind: "unpacked-asar-root",
      codexApp: null,
      sourceAsarRoot,
      packedAsarPath: null,
      extractedAsarRoot,
      extraction: null
    };
  }

  const codexApp = resolve(options.codexApp);
  const resourcesRoot = join(codexApp, "Contents", "Resources");
  const unpackedAppRoot = join(resourcesRoot, "app");
  const packedAsarPath = join(resourcesRoot, "app.asar");
  const unpackedRoot = join(resourcesRoot, "app.asar.unpacked");
  const extractedAsarRoot = join(outputDir, "app.asar.extracted");

  if (hasUnpackedAsarShape(unpackedAppRoot)) {
    cpSync(unpackedAppRoot, extractedAsarRoot, { recursive: true });
    return {
      sourceKind: "codex-app-unpacked-app-dir",
      codexApp,
      sourceAsarRoot: unpackedAppRoot,
      packedAsarPath: null,
      extractedAsarRoot,
      extraction: null
    };
  }

  if (!isFile(packedAsarPath)) {
    throw new Error(`Codex app does not contain Contents/Resources/app.asar or Contents/Resources/app: ${codexApp}`);
  }
  mkdirSync(extractedAsarRoot, { recursive: true });
  const extraction = extractPackedAsar({
    asarPath: packedAsarPath,
    unpackedRoot,
    outputDir: extractedAsarRoot
  });
  return {
    sourceKind: "codex-app-packed-asar",
    codexApp,
    sourceAsarRoot: null,
    packedAsarPath,
    extractedAsarRoot,
    extraction
  };
}

function runNodeScript(args) {
  const result = spawnSync(process.execPath, args, {
    cwd: root,
    encoding: "utf8"
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout || `Command failed: node ${args.join(" ")}`);
  }
  return result.stdout;
}

function patchExtractedAsar({ extractedAsarRoot, outputDir, adapterPath }) {
  const patchOutputRoot = join(outputDir, "patched");
  const stdout = runNodeScript([
    patcherPath,
    "--asar-root",
    extractedAsarRoot,
    "--output-dir",
    patchOutputRoot,
    "--adapter-path",
    adapterPath
  ]);
  return JSON.parse(stdout);
}

function analyzePatchedAsar(patchedAsarRoot) {
  const stdout = runNodeScript([
    analyzerPath,
    "--asar-root",
    patchedAsarRoot,
    "--compact"
  ]);
  return JSON.parse(stdout);
}

function checkPatchedSyntax(patch) {
  const files = [
    patch.patchedFiles?.main,
    patch.patchedFiles?.commentPreload
  ].filter(Boolean);
  return files.map((file) => {
    const result = spawnSync(process.execPath, ["--check", file], {
      cwd: root,
      encoding: "utf8"
    });
    if (result.status !== 0) {
      throw new Error(`Patched Codex JS syntax check failed for ${file}: ${result.stderr || result.stdout}`);
    }
    return {
      file,
      ok: true
    };
  });
}

function copyRunnableAppBundle({ codexApp, patchedAsarRoot, outputDir }) {
  if (!codexApp) {
    return null;
  }
  const materializedApp = join(outputDir, `${basename(codexApp, ".app")}-AppShot.app`);
  const resourcesRoot = join(materializedApp, "Contents", "Resources");
  const sourceResourcesRoot = join(codexApp, "Contents", "Resources");
  cpSync(codexApp, materializedApp, {
    recursive: true,
    filter(source) {
      const rel = relative(sourceResourcesRoot, source);
      return rel === "" ||
        (rel !== "app.asar" &&
          rel !== "app.asar.unpacked" &&
          !rel.startsWith(`app.asar.unpacked${sep}`) &&
          rel !== "app" &&
          !rel.startsWith(`app${sep}`));
    }
  });
  rmSync(join(resourcesRoot, "app.asar"), { force: true });
  rmSync(join(resourcesRoot, "app.asar.unpacked"), { recursive: true, force: true });
  rmSync(join(resourcesRoot, "app"), { recursive: true, force: true });
  cpSync(patchedAsarRoot, join(resourcesRoot, "app"), { recursive: true });
  return materializedApp;
}

function run(options) {
  if (options.help) {
    return usage();
  }
  const outputDir = resolve(options.outputDir || join(tmpdir(), `appshot-codex-host-${Date.now()}`));
  ensureEmptyOutputDir(outputDir, options.force);
  const source = resolveSource(options, outputDir);
  const patch = patchExtractedAsar({
    extractedAsarRoot: source.extractedAsarRoot,
    outputDir,
    adapterPath: resolve(options.adapterPath)
  });
  const syntaxChecks = checkPatchedSyntax(patch);
  const analysis = analyzePatchedAsar(patch.outputAsarRoot);
  const materializedApp = options.copyAppBundle
    ? copyRunnableAppBundle({
      codexApp: source.codexApp,
      patchedAsarRoot: patch.outputAsarRoot,
      outputDir
    })
    : null;

  return {
    format: "appshot-codex-host-materialization",
    source: "materialize_codex_host_patch_for_appshot",
    outputDir,
    adapterPath: resolve(options.adapterPath),
    sourceKind: source.sourceKind,
    codexApp: source.codexApp,
    packedAsarPath: source.packedAsarPath,
    sourceAsarRoot: source.sourceAsarRoot,
    extractedAsarRoot: source.extractedAsarRoot,
    extraction: source.extraction,
    patch,
    syntaxChecks,
    analysis: {
      format: analysis.format,
      package: analysis.package,
      files: analysis.files,
      channels: analysis.channels,
      preloadLifecycle: analysis.preloadLifecycle,
      remainingNonClaim: analysis.remainingNonClaim
    },
    materializedApp,
    launch: materializedApp ? {
      environment: {
        APPSHOT_CODEX_HOST_ADAPTER_PATH: resolve(options.adapterPath)
      },
      command: `APPSHOT_CODEX_HOST_ADAPTER_PATH=${JSON.stringify(resolve(options.adapterPath))} open -n ${JSON.stringify(materializedApp)}`,
      verification: "After launch, capture the Codex browser sidebar guest webview and expect privateCodexWebviewHostAttached to become true only from the live host context."
    } : null,
    privateHostStillRequiresLaunchingPatchedCodex: true
  };
}

try {
  const options = parseArgs(process.argv.slice(2));
  const payload = run(options);
  process.stdout.write(`${JSON.stringify(payload, null, options.pretty ? 2 : 0)}\n`);
} catch (error) {
  process.stderr.write(`appshot codex host materializer: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
}
