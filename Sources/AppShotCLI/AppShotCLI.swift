import AppShotCore
import Foundation

struct CLIOptions {
    var command: String = "capture"
    var outputPath: String?
    var screenshotPath: String?
    var includeScreenshot = false
    var includeOCR = false
    var pretty = false
    var format = "json"
    var maxDepth = 10
    var maxChildren = 120
    var maxOCRObservations = 240
    var accessibilityTimeoutSeconds = 8.0
    var screenshotTimeoutSeconds = 3.0
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
                    maxDepth: options.maxDepth,
                    maxChildren: options.maxChildren,
                    includeOCR: options.includeOCR,
                    maxOCRObservations: options.maxOCRObservations,
                    accessibilityTimeoutSeconds: options.accessibilityTimeoutSeconds,
                    screenshotTimeoutSeconds: options.screenshotTimeoutSeconds,
                    targetWindowID: options.windowID,
                    targetProcessIdentifier: options.pid,
                    targetBundleIdentifier: options.bundleID
                ))
            case "permissions":
                payload = AppShotCore.permissions(prompt: options.promptPermissions)
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
      appshot capture [--window-id id] [--pid pid] [--bundle-id id] [--include-screenshot] [--include-ocr] [--screenshot path.png] [--output path] [--format json|codex] [--max-depth n] [--max-children n] [--accessibility-timeout seconds] [--screenshot-timeout seconds] [--pretty]
      appshot permissions [--prompt]
      appshot list-windows [--pretty]

    Notes:
      Use list-windows first. Then pass the chosen windowID, pid, or bundleID to capture.
      Accessibility permission is required for rich text/UI trees.
      Screen Recording permission is required for screenshots.
      OCR is an explicit fallback for visible text that Accessibility does not expose.
      Accessibility content depends on what the target app exposes to macOS.
      --format codex prints a compact AppShot block similar to Codex built-in appshots.
    """)
}
