import AppShotCore
import Foundation

struct CLIOptions {
    var command: String = "capture"
    var outputPath: String?
    var screenshotPath: String?
    var includeScreenshot = false
    var browserAnnotationScreenshotsMode = browserAnnotationScreenshotsModeNecessary
    var browserInteractionMode = browserInteractionModeDefault
    var browserAnnotationEditorMode = browserAnnotationEditorModeComment
    var browserIsAgentControllingBrowser = false
    var browserCanUseTweaks = true
    var browserIsDesignModifierPressed = false
    var browserIsOriginalViewEnabled = false
    var browserIsTweaksEditorOpen = false
    var browserViewportScale = 1.0
    var browserZoomPercent: Double?
    var browserActiveDesignChange: JSONObject?
    var includeBrowserDOM = false
    var browserDOMTimeoutSeconds = 1.5
    var browserDOMFixture: JSONObject?
    var browserDOMInstallBridge = false
    var browserDOMClearBridgeLog = false
    var includeElectronDebugging = false
    var electronDebuggingTimeoutSeconds = 2.0
    var includeOCR = false
    var pretty = false
    var format = "json"
    var maxDepth = 60
    var maxChildren = 240
    var maxOCRObservations = 240
    var accessibilityTimeoutSeconds = 20.0
    var screenshotTimeoutSeconds = 3.0
    var preferRecentCache = true
    var writeCache = false
    var cacheMaxAgeSeconds = 15.0
    var cacheTrigger: String?
    var promptPermissions = false
    var windowID: UInt32?
    var pid: pid_t?
    var bundleID: String?
}

// @sm:node appshot.cli
// @sm:feature appshot.capture
// @sm:prev mcp.appshot.capture
// @sm:next appshot.core.capture
// @sm:deps AppShotCore
// @sm:evidence swift build && .build/debug/appshot status --pretty
@main
struct AppShotCLI {
    static func main() {
        do {
            let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            let payload: JSONObject
            switch options.command {
            case "capture":
                payload = try AppShotCore.capture(options: AppShotCaptureOptions(
                    screenshotPath: options.screenshotPath,
                    includeScreenshot: options.includeScreenshot,
                    browserAnnotationScreenshotsMode: options.browserAnnotationScreenshotsMode,
                    browserInteractionMode: options.browserInteractionMode,
                    browserAnnotationEditorMode: options.browserAnnotationEditorMode,
                    browserIsAgentControllingBrowser: options.browserIsAgentControllingBrowser,
                    browserCanUseTweaks: options.browserCanUseTweaks,
                    browserIsDesignModifierPressed: options.browserIsDesignModifierPressed,
                    browserIsOriginalViewEnabled: options.browserIsOriginalViewEnabled,
                    browserIsTweaksEditorOpen: options.browserIsTweaksEditorOpen,
                    browserViewportScale: options.browserViewportScale,
                    browserZoomPercent: options.browserZoomPercent,
                    browserActiveDesignChange: options.browserActiveDesignChange,
                    includeBrowserDOM: options.includeBrowserDOM,
                    browserDOMTimeoutSeconds: options.browserDOMTimeoutSeconds,
                    browserDOMFixture: options.browserDOMFixture,
                    browserDOMInstallBridge: options.browserDOMInstallBridge,
                    browserDOMClearBridgeLog: options.browserDOMClearBridgeLog,
                    includeElectronDebugging: options.includeElectronDebugging,
                    electronDebuggingTimeoutSeconds: options.electronDebuggingTimeoutSeconds,
                    maxDepth: options.maxDepth,
                    maxChildren: options.maxChildren,
                    includeOCR: options.includeOCR,
                    maxOCRObservations: options.maxOCRObservations,
                    accessibilityTimeoutSeconds: options.accessibilityTimeoutSeconds,
                    screenshotTimeoutSeconds: options.screenshotTimeoutSeconds,
                    preferRecentCache: options.preferRecentCache,
                    writeCache: options.writeCache,
                    cacheMaxAgeSeconds: options.cacheMaxAgeSeconds,
                    cacheTrigger: options.cacheTrigger,
                    targetWindowID: options.windowID,
                    targetProcessIdentifier: options.pid,
                    targetBundleIdentifier: options.bundleID
                ))
            case "permissions":
                payload = AppShotCore.permissions(prompt: options.promptPermissions)
            case "codex-apps-status":
                payload = AppShotCore.codexAppsStatus(prompt: options.promptPermissions)
            case "status":
                payload = AppShotCore.status(prompt: options.promptPermissions)
            case "list-windows":
                payload = AppShotCore.listWindows()
            case "help":
                printHelp()
                return
            default:
                throw AppShotError.usage("Unknown command: \(options.command)")
            }
            try write(payload: payload, to: options.outputPath, pretty: options.pretty, format: options.format)
        } catch {
            fputs("appshot: \(error)\n", stderr)
            fputs("Run `appshot help` for usage.\n", stderr)
            exit(1)
        }
    }
}

func parseArguments(_ args: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 0
    if let first = args.first, !first.hasPrefix("-") {
        options.command = first
        index = 1
    }

    while index < args.count {
        let arg = args[index]
        func nextValue() throws -> String {
            index += 1
            guard index < args.count else {
                throw AppShotError.usage("Missing value for \(arg)")
            }
            return args[index]
        }

        switch arg {
        case "--output", "-o":
            options.outputPath = try nextValue()
        case "--screenshot":
            options.screenshotPath = try nextValue()
        case "--include-screenshot":
            options.includeScreenshot = true
        case "--browser-annotation-screenshots-mode":
            let rawMode = try nextValue().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard isValidBrowserAnnotationScreenshotsMode(rawMode) else {
                throw AppShotError.usage("Unknown browser annotation screenshots mode: \(rawMode)")
            }
            options.browserAnnotationScreenshotsMode = rawMode
        case "--browser-interaction-mode":
            options.browserInteractionMode = normalizedBrowserInteractionMode(try nextValue())
        case "--browser-annotation-editor-mode":
            let rawMode = try nextValue().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard isValidBrowserAnnotationEditorMode(rawMode) else {
                throw AppShotError.usage("Unknown browser annotation editor mode: \(rawMode)")
            }
            options.browserAnnotationEditorMode = rawMode
        case "--browser-agent-controlling":
            options.browserIsAgentControllingBrowser = true
        case "--browser-disable-tweaks":
            options.browserCanUseTweaks = false
        case "--browser-design-modifier-pressed":
            options.browserIsDesignModifierPressed = true
        case "--browser-original-view-enabled":
            options.browserIsOriginalViewEnabled = true
        case "--browser-tweaks-editor-open":
            options.browserIsTweaksEditorOpen = true
        case "--browser-viewport-scale":
            options.browserViewportScale = Double(try nextValue()) ?? options.browserViewportScale
        case "--browser-zoom-percent":
            options.browserZoomPercent = Double(try nextValue())
        case "--browser-active-design-change-json":
            options.browserActiveDesignChange = try parseJSONObject(try nextValue(), optionName: arg)
        case "--include-browser-dom":
            options.includeBrowserDOM = true
        case "--browser-dom-timeout":
            options.browserDOMTimeoutSeconds = Double(try nextValue()) ?? options.browserDOMTimeoutSeconds
        case "--browser-dom-fixture-json":
            options.browserDOMFixture = try parseJSONObject(try nextValue(), optionName: arg)
            options.includeBrowserDOM = true
        case "--browser-dom-install-bridge":
            options.browserDOMInstallBridge = true
            options.includeBrowserDOM = true
        case "--browser-dom-clear-bridge-log":
            options.browserDOMClearBridgeLog = true
            options.includeBrowserDOM = true
        case "--include-electron-debugging":
            options.includeElectronDebugging = true
        case "--electron-debugging-timeout":
            options.electronDebuggingTimeoutSeconds = Double(try nextValue()) ?? options.electronDebuggingTimeoutSeconds
        case "--include-ocr":
            options.includeOCR = true
        case "--pretty":
            options.pretty = true
        case "--format":
            let format = try nextValue()
            guard ["json", "codex"].contains(format) else {
                throw AppShotError.usage("Unknown format: \(format)")
            }
            options.format = format
        case "--codex":
            options.format = "codex"
        case "--max-depth":
            options.maxDepth = Int(try nextValue()) ?? options.maxDepth
        case "--max-children":
            options.maxChildren = Int(try nextValue()) ?? options.maxChildren
        case "--max-ocr-observations":
            options.maxOCRObservations = Int(try nextValue()) ?? options.maxOCRObservations
        case "--accessibility-timeout":
            options.accessibilityTimeoutSeconds = Double(try nextValue()) ?? options.accessibilityTimeoutSeconds
        case "--screenshot-timeout":
            options.screenshotTimeoutSeconds = Double(try nextValue()) ?? options.screenshotTimeoutSeconds
        case "--ignore-cache", "--no-cache", "--fresh":
            options.preferRecentCache = false
        case "--write-cache":
            options.writeCache = true
        case "--cache-max-age":
            options.cacheMaxAgeSeconds = Double(try nextValue()) ?? options.cacheMaxAgeSeconds
        case "--cache-trigger":
            options.cacheTrigger = try nextValue()
        case "--window-id":
            options.windowID = UInt32(try nextValue())
        case "--pid":
            options.pid = pid_t(Int32(try nextValue()) ?? 0)
        case "--bundle-id":
            options.bundleID = try nextValue()
        case "--prompt":
            options.promptPermissions = true
        case "--help", "-h":
            options.command = "help"
        default:
            throw AppShotError.usage("Unknown option: \(arg)")
        }
        index += 1
    }
    return options
}

func parseJSONObject(_ text: String, optionName: String) throws -> JSONObject {
    guard let data = text.data(using: .utf8) else {
        throw AppShotError.usage("Invalid UTF-8 value for \(optionName)")
    }
    do {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? JSONObject else {
            throw AppShotError.usage("\(optionName) must be a JSON object")
        }
        return object
    } catch let error as AppShotError {
        throw error
    } catch {
        throw AppShotError.usage("Invalid JSON for \(optionName): \(error)")
    }
}

func write(payload: JSONObject, to path: String?, pretty: Bool, format: String) throws {
    let string: String
    if format == "codex" {
        let codex = payload["codex"] as? JSONObject
        string = codex?["text"] as? String ?? codexSummaryText(from: payload)
    } else {
        string = try AppShotCore.jsonString(payload, pretty: pretty)
    }
    let data = string.data(using: .utf8)!

    if let path {
        let url = URL(fileURLWithPath: path)
        do {
            try data.write(to: url)
        } catch {
            throw AppShotError.writeFailed(path)
        }
    } else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }
}

func printHelp() {
    print("""
    appshot - capture frontmost macOS app context as JSON

    Usage:
      appshot status [--prompt] [--pretty]
      appshot codex-apps-status [--prompt] [--pretty]
      appshot capture [--window-id id] [--pid pid] [--bundle-id id] [--include-screenshot] [--browser-annotation-screenshots-mode always|necessary] [--browser-interaction-mode mode] [--browser-annotation-editor-mode comment|design] [--browser-original-view-enabled] [--browser-design-modifier-pressed] [--browser-tweaks-editor-open] [--browser-active-design-change-json json] [--include-browser-dom] [--browser-dom-timeout seconds] [--browser-dom-fixture-json json] [--browser-dom-install-bridge] [--browser-dom-clear-bridge-log] [--include-electron-debugging] [--electron-debugging-timeout seconds] [--include-ocr] [--screenshot path.png] [--output path] [--format json|codex] [--max-depth n] [--max-children n] [--accessibility-timeout seconds] [--screenshot-timeout seconds] [--ignore-cache|--no-cache|--fresh] [--cache-max-age seconds] [--write-cache] [--cache-trigger label] [--pretty]
      appshot permissions [--prompt]
      appshot list-windows [--pretty]

    Notes:
      By default, capture may use a recent AppShot.app shortcut cache when no explicit target is passed.
      codex-apps-status reports AppShot's Codex accessible-connector readiness, tool surface, and permission blockers.
      Use --ignore-cache, --no-cache, or --fresh to force a fresh frontmost-window capture.
      AppShot.app writes the shortcut cache when both left and right Option keys are pressed together.
      Use list-windows first. Then pass the chosen windowID, pid, or bundleID to capture.
      Accessibility permission is required for rich text/UI trees.
      Screen Recording permission is required for screenshots.
      --browser-annotation-screenshots-mode always captures a screenshot for codexBrowserPayload by default.
      Browser runtime options populate codexBrowserRuntimeState using Codex browser-sidebar-runtime-sync field names.
      --include-browser-dom adds a timed Safari/Chrome DOM probe for image-drag sourceUrl and design-editor anchor candidates when Apple Events allows it.
      --browser-dom-install-bridge injects an optional page listener that records real browser-sidebar-runtime event logs in the current tab until reload.
      --include-electron-debugging scans local Electron/Chromium DevTools targets and samples DOM/AX through CDP when available.
      OCR is an explicit fallback for visible text that Accessibility does not expose.
      Accessibility content depends on what the target app exposes to macOS.
      --format codex prints a compact AppShot block similar to Codex built-in appshots.
    """)
}
