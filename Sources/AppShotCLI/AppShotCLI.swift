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
    var activateTarget = true
    var requestAppCapture = false
    var appCaptureTimeoutSeconds = 2.0
    var preferRecentCache = true
    var writeCache = false
    var cacheMaxAgeSeconds = 15.0
    var cacheTrigger: String?
    var promptPermissions = false
    var windowID: UInt32?
    var pid: pid_t?
    var bundleID: String?
    var windowTitle: String?
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
            let rawArgs = Array(CommandLine.arguments.dropFirst())
            if rawArgs.first == "rules" {
                let result = try runRulesCommand(Array(rawArgs.dropFirst()))
                try write(payload: result.payload, to: result.outputPath, pretty: result.pretty, format: "json")
                return
            }
            let options = try parseArguments(rawArgs)
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
                    activateTarget: options.activateTarget,
                    requestAppCapture: options.requestAppCapture,
                    appCaptureTimeoutSeconds: options.appCaptureTimeoutSeconds,
                    preferRecentCache: options.preferRecentCache,
                    writeCache: options.writeCache,
                    cacheMaxAgeSeconds: options.cacheMaxAgeSeconds,
                    cacheTrigger: options.cacheTrigger,
                    targetWindowID: options.windowID,
                    targetProcessIdentifier: options.pid,
                    targetBundleIdentifier: options.bundleID,
                    targetWindowTitle: options.windowTitle
                ))
            case "permissions":
                payload = AppShotCore.permissions(prompt: options.promptPermissions)
            case "codex-apps-status":
                payload = AppShotCore.codexAppsStatus(prompt: options.promptPermissions)
            case "codex-computer-use-status":
                payload = AppShotCore.codexComputerUseStatus()
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

struct RulesCommandResult {
    var payload: JSONObject
    var outputPath: String?
    var pretty: Bool
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
        case "--activate-target":
            options.activateTarget = true
        case "--no-activate-target":
            options.activateTarget = false
        case "--request-app-capture":
            options.requestAppCapture = true
        case "--app-capture-timeout":
            options.appCaptureTimeoutSeconds = Double(try nextValue()) ?? options.appCaptureTimeoutSeconds
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
        case "--window-title":
            options.windowTitle = try nextValue()
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

func runRulesCommand(_ args: [String]) throws -> RulesCommandResult {
    var index = 0
    let subcommand: String
    if let first = args.first, !first.hasPrefix("-") {
        subcommand = first
        index = 1
    } else {
        subcommand = "list"
    }

    var databasePath: String?
    var outputPath: String?
    var pretty = false
    var ruleJSON: String?
    var patchJSON: String?
    var id: String?
    var appBundleID: String?
    var bucketID: String?
    var windowTitle: String?
    var screenshotPath: String?
    var captureJSONPath: String?
    var codexTextPath: String?
    var sampleID: String?
    var ruleID: String?
    var corpus = "codex"
    var version: Int?
    var reason: String?
    var status: String?
    var limit = 50
    var anchors: [String] = []
    var anchorJSON: String?
    var outputTextPath: String?
    var metricWeightsJSON: String?
    var notes: String?

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
        case "--db", "--database":
            databasePath = try nextValue()
        case "--output", "-o":
            outputPath = try nextValue()
        case "--pretty":
            pretty = true
        case "--rule-json":
            ruleJSON = try loadTextArgument(try nextValue())
        case "--rule-json-file":
            ruleJSON = try readTextFile(try nextValue())
        case "--patch-json":
            patchJSON = try loadTextArgument(try nextValue())
        case "--patch-json-file":
            patchJSON = try readTextFile(try nextValue())
        case "--id":
            id = try nextValue()
        case "--app-bundle-id":
            appBundleID = try nextValue()
        case "--bucket-id":
            bucketID = try nextValue()
        case "--window-title":
            windowTitle = try nextValue()
        case "--screenshot":
            screenshotPath = try nextValue()
        case "--capture-json":
            captureJSONPath = try nextValue()
        case "--codex-text":
            codexTextPath = try nextValue()
        case "--sample-id":
            sampleID = try nextValue()
        case "--rule-id":
            ruleID = try nextValue()
        case "--corpus":
            corpus = try nextValue()
        case "--version":
            let raw = try nextValue()
            guard let parsed = Int(raw) else {
                throw AppShotError.usage("--version must be an integer")
            }
            version = parsed
        case "--reason":
            reason = try nextValue()
        case "--status":
            status = try nextValue()
        case "--limit":
            let raw = try nextValue()
            guard let parsed = Int(raw) else {
                throw AppShotError.usage("--limit must be an integer")
            }
            limit = parsed
        case "--anchor":
            anchors.append(try nextValue())
        case "--anchor-json":
            anchorJSON = try loadTextArgument(try nextValue())
        case "--anchor-json-file":
            anchorJSON = try readTextFile(try nextValue())
        case "--output-text":
            outputTextPath = try nextValue()
        case "--metric-weights-json":
            metricWeightsJSON = try loadTextArgument(try nextValue())
        case "--notes":
            notes = try nextValue()
        case "--help", "-h":
            return RulesCommandResult(payload: rulesHelpPayload(), outputPath: outputPath, pretty: true)
        default:
            throw AppShotError.usage("Unknown rules option: \(arg)")
        }
        index += 1
    }

    let payload: JSONObject
    switch subcommand {
    case "init":
        payload = try AppShotRuleStore.initialize(databasePath: databasePath)
    case "list":
        payload = try AppShotRuleStore.listRules(databasePath: databasePath, appBundleIdentifier: appBundleID)
    case "upsert":
        guard let ruleJSON else {
            throw AppShotError.usage("rules upsert requires --rule-json or --rule-json-file")
        }
        payload = try AppShotRuleStore.upsertRule(databasePath: databasePath, ruleJSONText: ruleJSON)
    case "patch":
        guard let id else {
            throw AppShotError.usage("rules patch requires --id")
        }
        guard let patchJSON else {
            throw AppShotError.usage("rules patch requires --patch-json or --patch-json-file")
        }
        payload = try AppShotRuleStore.patchRule(databasePath: databasePath, id: id, patchJSONText: patchJSON)
    case "delete":
        guard let id else {
            throw AppShotError.usage("rules delete requires --id")
        }
        payload = try AppShotRuleStore.deleteRule(databasePath: databasePath, id: id)
    case "archive":
        guard let id else {
            throw AppShotError.usage("rules archive requires --id")
        }
        payload = try AppShotRuleStore.setRuleEnabled(databasePath: databasePath, id: id, enabled: false, reason: reason)
    case "activate":
        guard let id else {
            throw AppShotError.usage("rules activate requires --id")
        }
        payload = try AppShotRuleStore.setRuleEnabled(databasePath: databasePath, id: id, enabled: true, reason: reason)
    case "select":
        guard let bucketID else {
            throw AppShotError.usage("rules select requires --bucket-id")
        }
        guard let ruleID else {
            throw AppShotError.usage("rules select requires --rule-id")
        }
        guard let version else {
            throw AppShotError.usage("rules select requires --version")
        }
        payload = try AppShotRuleStore.selectStrategy(databasePath: databasePath, bucketID: bucketID, ruleID: ruleID, version: version)
    case "measure":
        payload = try AppShotRuleStore.measure(
            databasePath: databasePath,
            sampleID: sampleID,
            appBundleIdentifier: appBundleID,
            bucketID: bucketID,
            limit: limit
        )
    case "history":
        payload = try AppShotRuleStore.history(databasePath: databasePath, id: id ?? ruleID, bucketID: bucketID, limit: limit)
    case "improvements":
        payload = try AppShotRuleStore.improvements(
            databasePath: databasePath,
            status: status,
            appBundleIdentifier: appBundleID,
            bucketID: bucketID,
            limit: limit
        )
    case "record-sample":
        payload = try AppShotRuleStore.recordSample(
            databasePath: databasePath,
            sampleID: sampleID,
            appBundleIdentifier: appBundleID,
            windowTitle: windowTitle,
            screenshotPath: screenshotPath,
            captureJSONPath: captureJSONPath,
            codexTextPath: codexTextPath,
            anchors: anchors,
            anchorJSONText: anchorJSON,
            notes: notes
        )
    case "apply":
        guard ruleJSON != nil || ruleID != nil else {
            throw AppShotError.usage("rules apply requires --rule-json, --rule-json-file, or --rule-id")
        }
        // For apply, --output writes the plain student text (for piping into
        // `rules evaluate --output-text`); the JSON payload still prints to stdout.
        payload = try AppShotRuleStore.applyRule(
            databasePath: databasePath,
            ruleJSONText: ruleJSON,
            ruleID: ruleID,
            captureJSONPath: captureJSONPath,
            sampleID: sampleID,
            outputPath: outputPath
        )
        return RulesCommandResult(payload: payload, outputPath: nil, pretty: pretty)
    case "evaluate":
        guard let sampleID else {
            throw AppShotError.usage("rules evaluate requires --sample-id")
        }
        let metricWeights = try metricWeightsJSON.map { try parseJSONObject($0, optionName: "--metric-weights-json") }
        payload = try AppShotRuleStore.evaluate(
            databasePath: databasePath,
            sampleID: sampleID,
            ruleID: ruleID,
            corpus: corpus,
            outputTextPath: outputTextPath,
            ruleJSONText: ruleJSON,
            metricWeights: metricWeights
        )
    case "help":
        payload = rulesHelpPayload()
        pretty = true
    default:
        throw AppShotError.usage("Unknown rules subcommand: \(subcommand)")
    }
    return RulesCommandResult(payload: payload, outputPath: outputPath, pretty: pretty)
}

func loadTextArgument(_ value: String) throws -> String {
    let expanded = (value as NSString).expandingTildeInPath
    if FileManager.default.fileExists(atPath: expanded) {
        return try readTextFile(expanded)
    }
    return value
}

func readTextFile(_ path: String) throws -> String {
    let expanded = (path as NSString).expandingTildeInPath
    guard let text = try? String(contentsOfFile: expanded, encoding: .utf8) else {
        throw AppShotError.usage("Failed to read \(path)")
    }
    return text
}

func rulesHelpPayload() -> JSONObject {
    [
        "usage": [
            "appshot rules init [--db path] [--pretty]",
            "appshot rules list [--db path] [--app-bundle-id id] [--pretty]",
            "appshot rules upsert --rule-json '{...}' [--db path]",
            "appshot rules upsert --rule-json-file rule.json [--db path]",
            "appshot rules patch --id rule-id --patch-json '{...}' [--db path]",
            "appshot rules delete --id rule-id [--db path]",
            "appshot rules archive|activate --id rule-id [--reason text] [--db path]",
            "appshot rules measure [--sample-id id] [--app-bundle-id id] [--bucket-id id] [--limit n] [--db path]",
            "appshot rules history [--id rule-id] [--bucket-id id] [--limit n] [--db path]",
            "appshot rules improvements [--status open] [--app-bundle-id id] [--bucket-id id] [--limit n] [--db path]",
            "appshot rules select --bucket-id id --rule-id id --version n [--db path]",
            "appshot rules record-sample --sample-id id --capture-json capture.json --codex-text capture.txt [--anchor regex...] [--anchor-json-file anchors.json] [--db path]",
            "appshot rules apply --rule-id id|--rule-json-file rule.json --capture-json capture.json [--output student.txt] [--db path]",
            "appshot rules evaluate --sample-id id [--output-text student.txt] [--rule-id id|--rule-json-file rule.json] [--corpus codex|capture|combined] [--metric-weights-json '{...}'] [--db path]"
        ],
        "ruleShape": [
            "id": "vscode-terminal-visible-text-v1",
            "scope": "app",
            "match": [
                "appBundleIds": ["com.microsoft.VSCode"],
                "windowTitleRegex": ".*",
                "treeRegex": "Terminal|AXTextArea|AXGroup"
            ],
            "action": [
                "includeChildren": true,
                "promoteTextKeys": ["textContent", "value", "description", "visibleTextFragments"],
                "fallbackOCR": true
            ],
            "priority": 80,
            "confidence": 0.72,
            "enabled": true
        ] as JSONObject
    ]
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
      appshot codex-computer-use-status [--pretty]
      appshot capture [--window-id id] [--window-title title] [--pid pid] [--bundle-id id] [--activate-target|--no-activate-target] [--request-app-capture] [--app-capture-timeout seconds] [--include-screenshot] [--browser-annotation-screenshots-mode always|necessary] [--browser-interaction-mode mode] [--browser-annotation-editor-mode comment|design] [--browser-original-view-enabled] [--browser-design-modifier-pressed] [--browser-tweaks-editor-open] [--browser-active-design-change-json json] [--include-browser-dom] [--browser-dom-timeout seconds] [--browser-dom-fixture-json json] [--browser-dom-install-bridge] [--browser-dom-clear-bridge-log] [--include-electron-debugging] [--electron-debugging-timeout seconds] [--include-ocr] [--screenshot path.png] [--output path] [--format json|codex] [--max-depth n] [--max-children n] [--accessibility-timeout seconds] [--screenshot-timeout seconds] [--ignore-cache|--no-cache|--fresh] [--cache-max-age seconds] [--write-cache] [--cache-trigger label] [--pretty]
      appshot rules init|list|upsert|patch|delete|archive|activate|measure|history|improvements|select|record-sample|evaluate [--db path] [--pretty]
      appshot permissions [--prompt]
      appshot list-windows [--pretty]

    Notes:
      By default, capture may use a recent AppShot.app shortcut cache when no explicit target is passed.
      codex-apps-status reports AppShot's Codex accessible-connector readiness, tool surface, and permission blockers.
      codex-computer-use-status reports Codex Computer Use service, app approval, and host-bridge parity diagnostics.
      Use --ignore-cache, --no-cache, or --fresh to force a fresh frontmost-window capture.
      AppShot.app writes the shortcut cache when both left and right Option keys are pressed together.
      Use list-windows first. Then pass the chosen windowID, window title, pid, or bundleID to capture.
      --window-title can target Accessibility-only Electron windows that are visible to macOS AX but absent from CGWindow.
      Target activation is enabled by default so explicit captures more closely match Codex's front-window AppShot behavior.
      --request-app-capture asks the running GUI AppShot.app to perform the capture and waits for its shared cache before falling back to direct CLI capture.
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
      rules stores app-specific extraction rules, training samples, expected anchors, rule-version outputs, measurements, history, selected strategies, and improvement pools in SQLite. Rule evaluation defaults to the Codex text corpus; pass --corpus capture or --corpus combined for diagnostic comparisons.
    """)
}
