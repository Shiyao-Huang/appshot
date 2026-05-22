import AppShotCore
import Foundation

struct CLIOptions {
    var command: String = "capture"
    var outputPath: String?
    var screenshotPath: String?
    var includeScreenshot = false
    var pretty = false
    var maxDepth = 6
    var maxChildren = 120
    var promptPermissions = false
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
                    maxChildren: options.maxChildren
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
            try write(payload: payload, to: options.outputPath, pretty: options.pretty)
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
        case "--pretty":
            options.pretty = true
        case "--max-depth":
            options.maxDepth = Int(try nextValue()) ?? options.maxDepth
        case "--max-children":
            options.maxChildren = Int(try nextValue()) ?? options.maxChildren
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

func write(payload: JSONObject, to path: String?, pretty: Bool) throws {
    let string = try AppShotCore.jsonString(payload, pretty: pretty)
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
      appshot capture [--include-screenshot] [--screenshot path.png] [--output path.json] [--pretty]
      appshot permissions [--prompt]
      appshot list-windows [--pretty]

    Notes:
      Accessibility permission is required for rich text/UI trees.
      Screen Recording permission is required for screenshots.
      Accessibility content depends on what the target app exposes to macOS.
    """)
}
