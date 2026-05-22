import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public typealias JSONObject = [String: Any]

public struct AppShotCaptureOptions {
    public var screenshotPath: String?
    public var includeScreenshot: Bool
    public var maxDepth: Int
    public var maxChildren: Int
    public var accessibilityTimeoutSeconds: TimeInterval
    public var screenshotTimeoutSeconds: TimeInterval

    public init(
        screenshotPath: String? = nil,
        includeScreenshot: Bool = false,
        maxDepth: Int = 6,
        maxChildren: Int = 120,
        accessibilityTimeoutSeconds: TimeInterval = 2.0,
        screenshotTimeoutSeconds: TimeInterval = 3.0
    ) {
        self.screenshotPath = screenshotPath
        self.includeScreenshot = includeScreenshot
        self.maxDepth = maxDepth
        self.maxChildren = maxChildren
        self.accessibilityTimeoutSeconds = accessibilityTimeoutSeconds
        self.screenshotTimeoutSeconds = screenshotTimeoutSeconds
    }
}

public enum AppShotError: Error, CustomStringConvertible {
    case usage(String)
    case noFrontmostApplication
    case jsonEncoding
    case writeFailed(String)
    case screenshotTimedOut(String)

    public var description: String {
        switch self {
        case .usage(let message):
            return message
        case .noFrontmostApplication:
            return "No frontmost application was found."
        case .jsonEncoding:
            return "Failed to encode AppShot JSON."
        case .writeFailed(let path):
            return "Failed to write output to \(path)."
        case .screenshotTimedOut(let path):
            return "Screenshot timed out before writing \(path)."
        }
    }
}

// @sm:node appshot.core.capture
// @sm:feature appshot.capture
// @sm:prev appshot.app.status,appshot.cli
// @sm:next macos.accessibility.snapshot
// @sm:deps AppKit,ApplicationServices,CoreGraphics,screencapture
// @sm:evidence swift build && .build/debug/appshot status --pretty
public enum AppShotCore {
    public static func capture(options: AppShotCaptureOptions = AppShotCaptureOptions()) throws -> JSONObject {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw AppShotError.noFrontmostApplication
        }

        let pid = app.processIdentifier
        let windows = windowsForPID(pid)
        let primaryWindow = windows.first
        let windowID = primaryWindow?["windowID"] as? UInt32
        let screenshot = try maybeCaptureScreenshot(
            include: options.includeScreenshot || options.screenshotPath != nil,
            requestedPath: options.screenshotPath,
            windowID: windowID,
            timeoutSeconds: options.screenshotTimeoutSeconds
        )

        var payload: JSONObject = [
            "schemaVersion": 1,
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "permissions": permissions(prompt: false),
            "frontmostApplication": appInfo(app),
            "windows": windows,
            "accessibility": accessibilitySnapshot(
                pid: pid,
                maxDepth: options.maxDepth,
                maxChildren: options.maxChildren,
                timeoutSeconds: options.accessibilityTimeoutSeconds
            )
        ]

        if let primaryWindow {
            payload["primaryWindow"] = primaryWindow
        }
        if let screenshot {
            payload["screenshot"] = screenshot
        }
        return payload
    }

    public static func permissions(prompt: Bool) -> JSONObject {
        let axOptions = prompt
            ? ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            : nil

        var screenCapture: Bool
        if #available(macOS 10.15, *) {
            screenCapture = CGPreflightScreenCaptureAccess()
            if prompt && !screenCapture {
                screenCapture = CGRequestScreenCaptureAccess()
            }
        } else {
            screenCapture = true
        }

        return [
            "accessibility": AXIsProcessTrustedWithOptions(axOptions),
            "screenRecording": screenCapture
        ]
    }

    public static func listWindows() -> JSONObject {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { app -> JSONObject in
                var out = appInfo(app)
                out["windows"] = windowsForPID(app.processIdentifier)
                return out
            }
        return [
            "schemaVersion": 1,
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "applications": apps
        ]
    }

    public static func status(prompt: Bool = false) -> JSONObject {
        let permissionPayload = permissions(prompt: prompt)
        let hasAccessibility = permissionPayload["accessibility"] as? Bool ?? false
        let hasScreenRecording = permissionPayload["screenRecording"] as? Bool ?? false
        let frontmost = NSWorkspace.shared.frontmostApplication
        let windows = frontmost.map { windowsForPID($0.processIdentifier) } ?? []
        let primaryWindow = windows.first

        var blockers: [String] = []
        if !hasAccessibility {
            blockers.append("Accessibility permission is off; text/UI tree will be shallow.")
        }
        if !hasScreenRecording {
            blockers.append("Screen Recording permission is off; screenshots may fail.")
        }
        if frontmost == nil {
            blockers.append("No frontmost application is available.")
        }

        var payload: JSONObject = [
            "schemaVersion": 1,
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "state": blockers.isEmpty ? "ready" : "needsAttention",
            "permissions": permissionPayload,
            "windowCount": windows.count,
            "blockers": blockers
        ]

        if let frontmost {
            payload["frontmostApplication"] = appInfo(frontmost)
        }
        if let primaryWindow {
            payload["primaryWindow"] = primaryWindow
        }
        return payload
    }

    public static func jsonString(_ payload: JSONObject, pretty: Bool = true) throws -> String {
        var options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
        if pretty {
            options.insert(.prettyPrinted)
            options.insert(.sortedKeys)
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: options),
              let string = String(data: data, encoding: .utf8) else {
            throw AppShotError.jsonEncoding
        }
        return string
    }
}

public func appInfo(_ app: NSRunningApplication) -> JSONObject {
    [
        "localizedName": app.localizedName ?? "",
        "bundleIdentifier": app.bundleIdentifier ?? "",
        "bundleURL": app.bundleURL?.path ?? "",
        "executableURL": app.executableURL?.path ?? "",
        "processIdentifier": app.processIdentifier,
        "activationPolicy": app.activationPolicy.rawValue
    ]
}

public func windowsForPID(_ pid: pid_t) -> [JSONObject] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [JSONObject] else {
        return []
    }

    return raw.compactMap { info in
        guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
              ownerPID == pid,
              let layer = info[kCGWindowLayer as String] as? Int,
              layer == 0 else {
            return nil
        }

        var out: JSONObject = [
            "windowID": info[kCGWindowNumber as String] as? UInt32 ?? 0,
            "ownerName": info[kCGWindowOwnerName as String] as? String ?? "",
            "title": info[kCGWindowName as String] as? String ?? "",
            "layer": layer,
            "alpha": info[kCGWindowAlpha as String] as? Double ?? 0
        ]

        if let bounds = info[kCGWindowBounds as String] as? JSONObject {
            out["bounds"] = normalizedBounds(bounds)
            if let width = bounds["Width"] as? CGFloat, let height = bounds["Height"] as? CGFloat {
                out["area"] = width * height
            }
        }
        return out
    }
    .sorted {
        (($0["area"] as? CGFloat) ?? 0) > (($1["area"] as? CGFloat) ?? 0)
    }
}

public func normalizedBounds(_ bounds: JSONObject) -> JSONObject {
    [
        "x": bounds["X"] ?? 0,
        "y": bounds["Y"] ?? 0,
        "width": bounds["Width"] ?? 0,
        "height": bounds["Height"] ?? 0
    ]
}

// @sm:node macos.accessibility.snapshot
// @sm:feature appshot.capture
// @sm:prev appshot.core.capture
// @sm:next appshot.json.payload
// @sm:deps AXUIElement,AXAttribute,AXValue
// @sm:evidence appshot capture --max-depth 2 --pretty
public func accessibilitySnapshot(
    pid: pid_t,
    maxDepth: Int,
    maxChildren: Int,
    timeoutSeconds: TimeInterval = 2.0
) -> JSONObject {
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 0.25)
    var focused: AnyObject?
    let focusedResult = AXUIElementCopyAttributeValue(
        appElement,
        kAXFocusedWindowAttribute as CFString,
        &focused
    )

    let root = focusedResult == .success
        ? (focused as! AXUIElement)
        : appElement
    AXUIElementSetMessagingTimeout(root, 0.25)

    return [
        "trusted": AXIsProcessTrusted(),
        "timeoutSeconds": timeoutSeconds,
        "root": elementSnapshot(
            root,
            depth: 0,
            maxDepth: maxDepth,
            maxChildren: maxChildren,
            deadline: Date().addingTimeInterval(timeoutSeconds)
        )
    ]
}

public func elementSnapshot(
    _ element: AXUIElement,
    depth: Int,
    maxDepth: Int,
    maxChildren: Int,
    deadline: Date
) -> JSONObject {
    var out: JSONObject = [:]
    guard Date() < deadline else {
        return ["truncatedByTimeout": true]
    }

    AXUIElementSetMessagingTimeout(element, 0.25)
    let attributes = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXTitleAttribute,
        kAXValueAttribute,
        kAXDescriptionAttribute,
        kAXHelpAttribute,
        kAXIdentifierAttribute,
        kAXSelectedTextAttribute
    ]

    for attribute in attributes {
        if let value = copyAXValue(element, attribute) {
            out[attribute.replacingOccurrences(of: "AX", with: "").lowercasedFirst] = jsonSafe(value)
        }
    }

    if let position = copyAXValue(element, kAXPositionAttribute),
       let point = axPoint(position) {
        out["position"] = ["x": point.x, "y": point.y]
    }
    if let size = copyAXValue(element, kAXSizeAttribute),
       let cgSize = axSize(size) {
        out["size"] = ["width": cgSize.width, "height": cgSize.height]
    }

    guard depth < maxDepth,
          let childrenValue = copyAXValue(element, kAXChildrenAttribute) as? [AXUIElement] else {
        return out
    }

    let limited = Array(childrenValue.prefix(maxChildren))
    out["children"] = limited.map {
        elementSnapshot(
            $0,
            depth: depth + 1,
            maxDepth: maxDepth,
            maxChildren: maxChildren,
            deadline: deadline
        )
    }
    if childrenValue.count > maxChildren {
        out["childrenTruncated"] = childrenValue.count - maxChildren
    }
    return out
}

public func copyAXValue(_ element: AXUIElement, _ attribute: String) -> Any? {
    AXUIElementSetMessagingTimeout(element, 0.25)
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else {
        return nil
    }
    return value
}

public func axPoint(_ value: Any) -> CGPoint? {
    guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else {
        return nil
    }
    var point = CGPoint.zero
    AXValueGetValue(axValue, .cgPoint, &point)
    return point
}

public func axSize(_ value: Any) -> CGSize? {
    guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgSize else {
        return nil
    }
    var size = CGSize.zero
    AXValueGetValue(axValue, .cgSize, &size)
    return size
}

public func jsonSafe(_ value: Any) -> Any {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number
    case let array as [Any]:
        return array.map(jsonSafe)
    case let dictionary as [String: Any]:
        return dictionary.mapValues(jsonSafe)
    default:
        return String(describing: value)
    }
}

public func maybeCaptureScreenshot(
    include: Bool,
    requestedPath: String?,
    windowID: UInt32?,
    timeoutSeconds: TimeInterval = 3.0
) throws -> JSONObject? {
    guard include else {
        return nil
    }

    let path = requestedPath ?? defaultScreenshotPath()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

    if let windowID, windowID != 0 {
        process.arguments = ["-x", "-l", String(windowID), path]
    } else {
        process.arguments = ["-x", path]
    }

    try process.run()
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }

    let timedOut = process.isRunning
    if timedOut {
        process.terminate()
    }
    process.waitUntilExit()

    return [
        "path": path,
        "windowID": windowID as Any,
        "exitStatus": process.terminationStatus,
        "timedOut": timedOut,
        "timeoutSeconds": timeoutSeconds,
        "captured": !timedOut && process.terminationStatus == 0 && FileManager.default.fileExists(atPath: path)
    ]
}

public func defaultScreenshotPath() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return FileManager.default.currentDirectoryPath + "/appshot-\(formatter.string(from: Date())).png"
}

extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
