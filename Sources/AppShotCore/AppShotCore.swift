import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Vision

public typealias JSONObject = [String: Any]

public struct AppShotCaptureOptions {
    public var screenshotPath: String?
    public var includeScreenshot: Bool
    public var maxDepth: Int
    public var maxChildren: Int
    public var includeOCR: Bool
    public var maxOCRObservations: Int
    public var accessibilityTimeoutSeconds: TimeInterval
    public var screenshotTimeoutSeconds: TimeInterval
    public var targetWindowID: UInt32?
    public var targetProcessIdentifier: pid_t?
    public var targetBundleIdentifier: String?

    public init(
        screenshotPath: String? = nil,
        includeScreenshot: Bool = false,
        maxDepth: Int = 10,
        maxChildren: Int = 120,
        includeOCR: Bool = false,
        maxOCRObservations: Int = 240,
        accessibilityTimeoutSeconds: TimeInterval = 2.0,
        screenshotTimeoutSeconds: TimeInterval = 3.0,
        targetWindowID: UInt32? = nil,
        targetProcessIdentifier: pid_t? = nil,
        targetBundleIdentifier: String? = nil
    ) {
        self.screenshotPath = screenshotPath
        self.includeScreenshot = includeScreenshot
        self.maxDepth = maxDepth
        self.maxChildren = maxChildren
        self.includeOCR = includeOCR
        self.maxOCRObservations = maxOCRObservations
        self.accessibilityTimeoutSeconds = accessibilityTimeoutSeconds
        self.screenshotTimeoutSeconds = screenshotTimeoutSeconds
        self.targetWindowID = targetWindowID
        self.targetProcessIdentifier = targetProcessIdentifier
        self.targetBundleIdentifier = targetBundleIdentifier
    }
}

public enum AppShotError: Error, CustomStringConvertible {
    case usage(String)
    case noFrontmostApplication
    case targetNotFound(String)
    case jsonEncoding
    case writeFailed(String)
    case screenshotTimedOut(String)

    public var description: String {
        switch self {
        case .usage(let message):
            return message
        case .noFrontmostApplication:
            return "No frontmost application was found."
        case .targetNotFound(let target):
            return "No visible window matched target: \(target)."
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
        let target = try resolveCaptureTarget(
            windowID: options.targetWindowID,
            processIdentifier: options.targetProcessIdentifier,
            bundleIdentifier: options.targetBundleIdentifier
        )
        let app = target.application
        let pid = app.processIdentifier
        let windows = target.windows
        let primaryWindow = target.window ?? windows.first
        let windowID = primaryWindow?["windowID"] as? UInt32
        let screenshot = try maybeCaptureScreenshot(
            include: options.includeScreenshot || options.screenshotPath != nil || options.includeOCR,
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
                targetWindow: primaryWindow,
                maxDepth: options.maxDepth,
                maxChildren: options.maxChildren,
                timeoutSeconds: options.accessibilityTimeoutSeconds
            )
        ]

        if let targetSelection = target.selection {
            payload["targetSelection"] = targetSelection
        }
        if let primaryWindow {
            payload["primaryWindow"] = primaryWindow
        }
        if let screenshot {
            payload["screenshot"] = screenshot
        }
        if options.includeOCR {
            let path = (screenshot?["path"] as? String) ?? options.screenshotPath
            payload["ocr"] = ocrSnapshot(
                screenshotPath: path,
                screenshotCaptured: screenshot?["captured"] as? Bool ?? false,
                maxObservations: options.maxOCRObservations
            )
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
                out["captureParameters"] = [
                    "pid": app.processIdentifier,
                    "bundleID": app.bundleIdentifier ?? ""
                ]
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

private struct CaptureTarget {
    var application: NSRunningApplication
    var windows: [JSONObject]
    var window: JSONObject?
    var selection: JSONObject?
}

private func resolveCaptureTarget(
    windowID: UInt32?,
    processIdentifier: pid_t?,
    bundleIdentifier: String?
) throws -> CaptureTarget {
    if let windowID {
        if let candidate = windowCandidate(windowID: windowID),
           let application = application(from: candidate),
           let window = candidate["window"] as? JSONObject {
            return CaptureTarget(
                application: application,
                windows: windowsForPID(application.processIdentifier),
                window: window,
                selection: [
                    "type": "windowID",
                    "windowID": windowID
                ]
            )
        }
        throw AppShotError.targetNotFound(String(windowID))
    }

    if let processIdentifier,
       let application = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == processIdentifier }) {
        let windows = windowsForPID(application.processIdentifier)
        return CaptureTarget(
            application: application,
            windows: windows,
            window: windows.first,
            selection: [
                "type": "pid",
                "pid": processIdentifier
            ]
        )
    }

    if let bundleIdentifier,
       !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let application = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
        let windows = windowsForPID(application.processIdentifier)
        return CaptureTarget(
            application: application,
            windows: windows,
            window: windows.first,
            selection: [
                "type": "bundleID",
                "bundleID": bundleIdentifier
            ]
        )
    }

    guard let app = NSWorkspace.shared.frontmostApplication else {
        throw AppShotError.noFrontmostApplication
    }
    let windows = windowsForPID(app.processIdentifier)
    return CaptureTarget(application: app, windows: windows, window: windows.first, selection: nil)
}

private func application(from candidate: JSONObject) -> NSRunningApplication? {
    guard let appPayload = candidate["application"] as? JSONObject,
          let pid = appPayload["processIdentifier"] as? pid_t else {
        return nil
    }
    return NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
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
            "ownerPID": ownerPID,
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
        out["captureParameters"] = [
            "windowID": out["windowID"] ?? 0,
            "pid": ownerPID
        ]
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

private func windowCandidate(windowID: UInt32) -> JSONObject? {
    allWindowCandidates().first { candidate in
        guard let window = candidate["window"] as? JSONObject,
              let candidateWindowID = window["windowID"] as? UInt32 else {
            return false
        }
        return candidateWindowID == windowID
    }
}

private func allWindowCandidates() -> [JSONObject] {
    NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular }
        .flatMap { app -> [JSONObject] in
            let appPayload = appInfo(app)
            return windowsForPID(app.processIdentifier).map { window in
                [
                    "application": appPayload,
                    "window": window
                ]
            }
        }
}

// @sm:node macos.accessibility.snapshot
// @sm:feature appshot.capture
// @sm:prev appshot.core.capture
// @sm:next appshot.json.payload
// @sm:deps AXUIElement,AXAttribute,AXValue
// @sm:evidence appshot capture --max-depth 2 --pretty
public func accessibilitySnapshot(
    pid: pid_t,
    targetWindow: JSONObject? = nil,
    maxDepth: Int,
    maxChildren: Int,
    timeoutSeconds: TimeInterval = 2.0
) -> JSONObject {
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 0.25)
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    var focusedWindow: AnyObject?
    let focusedWindowResult = AXUIElementCopyAttributeValue(
        appElement,
        kAXFocusedWindowAttribute as CFString,
        &focusedWindow
    )
    var focusedElement: AnyObject?
    let focusedElementResult = AXUIElementCopyAttributeValue(
        appElement,
        kAXFocusedUIElementAttribute as CFString,
        &focusedElement
    )
    var mainWindow: AnyObject?
    let mainWindowResult = AXUIElementCopyAttributeValue(
        appElement,
        kAXMainWindowAttribute as CFString,
        &mainWindow
    )

    var visited = Set<String>()
    let targetAXWindow = targetWindow.flatMap {
        matchingAXWindow(appElement: appElement, targetWindow: $0)
    }
    let rootElement = targetAXWindow != nil
        ? targetAXWindow!
        : focusedWindowResult == .success
        ? (focusedWindow as! AXUIElement)
        : appElement
    let root = elementSnapshot(
        rootElement,
        depth: 0,
        maxDepth: maxDepth,
        maxChildren: maxChildren,
        deadline: deadline,
        visited: &visited
    )

    var payload: JSONObject = [
        "trusted": AXIsProcessTrusted(),
        "timeoutSeconds": timeoutSeconds,
        "rootSource": targetAXWindow != nil ? "targetWindow" : focusedWindowResult == .success ? "focusedWindow" : "application",
        "root": root
    ]

    if let targetWindow {
        payload["targetWindow"] = targetWindow
    }

    if focusedElementResult == .success,
       let focusedElement {
        let focusedAXElement = focusedElement as! AXUIElement
        if !sameAXElement(focusedAXElement, rootElement) {
            payload["focusedElement"] = elementSnapshot(
                focusedAXElement,
                depth: 0,
                maxDepth: max(1, min(maxDepth, 4)),
                maxChildren: maxChildren,
                deadline: deadline,
                visited: &visited
            )
        }
    }

    if mainWindowResult == .success,
       let mainWindow {
        let mainAXWindow = mainWindow as! AXUIElement
        if !sameAXElement(mainAXWindow, rootElement) {
            payload["mainWindow"] = elementSnapshot(
                mainAXWindow,
                depth: 0,
                maxDepth: max(1, min(maxDepth, 4)),
                maxChildren: maxChildren,
                deadline: deadline,
                visited: &visited
            )
        }
    }

    let documents = documentReferences(from: payload)
    if !documents.isEmpty {
        payload["documentReferences"] = documents
    }

    let lines = accessibilityTextLines(from: payload)
    payload["text"] = lines.joined(separator: "\n")
    payload["textLineCount"] = lines.count

    return payload
}

public func elementSnapshot(
    _ element: AXUIElement,
    depth: Int,
    maxDepth: Int,
    maxChildren: Int,
    deadline: Date,
    visited: inout Set<String>
) -> JSONObject {
    var out: JSONObject = [:]
    guard Date() < deadline else {
        return ["truncatedByTimeout": true]
    }

    AXUIElementSetMessagingTimeout(element, 0.25)
    let elementID = axElementID(element)
    if visited.contains(elementID) {
        return ["cycle": true]
    }
    visited.insert(elementID)

    let fixedAttributes = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXTitleAttribute,
        kAXValueAttribute,
        kAXDescriptionAttribute,
        kAXHelpAttribute,
        kAXIdentifierAttribute,
        kAXSelectedTextAttribute,
        "AXPlaceholderValue",
        "AXRoleDescription",
        "AXDocument",
        "AXFilename",
        "AXURL"
    ]
    let attributes = dedupeStrings(fixedAttributes + axAttributeNames(element))
    var childAttributes = axChildAttributes

    for attribute in attributes {
        if let value = copyAXValue(element, attribute) {
            if valueContainsAXElement(value) {
                childAttributes.append(attribute)
            } else if let safeValue = jsonSafeAXValue(value) {
                out[attribute.replacingOccurrences(of: "AX", with: "").lowercasedFirst] = safeValue
            }
        }
    }

    if let parameterizedText = axParameterizedText(element) {
        out["textContent"] = parameterizedText
    }

    if let position = copyAXValue(element, kAXPositionAttribute),
       let point = axPoint(position) {
        out["position"] = ["x": point.x, "y": point.y]
    }
    if let size = copyAXValue(element, kAXSizeAttribute),
       let cgSize = axSize(size) {
        out["size"] = ["width": cgSize.width, "height": cgSize.height]
    }

    guard depth < maxDepth else {
        return out
    }

    for childAttribute in dedupeStrings(childAttributes) {
        guard Date() < deadline else {
            out["truncatedByTimeout"] = true
            return out
        }

        let children = axChildElements(element, attribute: childAttribute)
        guard !children.isEmpty else {
            continue
        }

        let key = childAttribute.replacingOccurrences(of: "AX", with: "").lowercasedFirst
        let limited = Array(children.prefix(maxChildren))
        out[key] = limited.map {
            elementSnapshot(
                $0,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxChildren: maxChildren,
                deadline: deadline,
                visited: &visited
            )
        }
        if children.count > maxChildren {
            out["\(key)Truncated"] = children.count - maxChildren
        }
    }
    return out
}

let axChildAttributes = [
    kAXWindowsAttribute,
    kAXChildrenAttribute,
    "AXVisibleChildren",
    "AXSelectedChildren",
    "AXContents",
    "AXRows",
    "AXVisibleRows",
    "AXColumns",
    "AXVisibleColumns",
    "AXTabs",
    "AXChildrenInNavigationOrder",
    "AXLinkedUIElements",
    "AXTitleUIElement",
    "AXServesAsTitleForUIElements",
    "AXHeader",
    "AXEditedAncestor"
]

public func axAttributeNames(_ element: AXUIElement) -> [String] {
    AXUIElementSetMessagingTimeout(element, 0.25)
    var names: CFArray?
    let result = AXUIElementCopyAttributeNames(element, &names)
    guard result == .success,
          let names = names as? [String] else {
        return []
    }
    return names
}

public func axChildElements(_ element: AXUIElement, attribute: String) -> [AXUIElement] {
    guard let value = copyAXValue(element, attribute) else {
        return []
    }
    if isAXUIElement(value) {
        return [value as! AXUIElement]
    }
    if let elements = value as? [AXUIElement] {
        return dedupeAXElements(elements)
    }
    return []
}

public func matchingAXWindow(appElement: AXUIElement, targetWindow: JSONObject) -> AXUIElement? {
    let windows = dedupeAXElements(
        axChildElements(appElement, attribute: kAXWindowsAttribute) +
        axChildElements(appElement, attribute: "AXVisibleChildren") +
        axChildElements(appElement, attribute: kAXChildrenAttribute)
    )
    guard !windows.isEmpty else {
        return nil
    }

    let targetTitle = (targetWindow["title"] as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let targetBounds = targetWindow["bounds"] as? JSONObject
    var best: (score: Double, element: AXUIElement)?

    for window in windows {
        var score = 0.0
        let axTitle = (copyAXValue(window, kAXTitleAttribute) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !targetTitle.isEmpty && !axTitle.isEmpty {
            if axTitle == targetTitle {
                score += 120
            } else if axTitle.contains(targetTitle) || targetTitle.contains(axTitle) {
                score += 50
            }
        }

        if let targetBounds,
           let position = copyAXValue(window, kAXPositionAttribute),
           let size = copyAXValue(window, kAXSizeAttribute),
           let point = axPoint(position),
           let cgSize = axSize(size),
           let x = numberValue(targetBounds["x"]),
           let y = numberValue(targetBounds["y"]),
           let width = numberValue(targetBounds["width"]),
           let height = numberValue(targetBounds["height"]) {
            let delta = abs(point.x - x) + abs(point.y - y) + abs(cgSize.width - width) + abs(cgSize.height - height)
            if delta < 12 {
                score += 120
            } else if delta < 80 {
                score += 60
            }
        }

        if score > (best?.score ?? 0) {
            best = (score, window)
        }
    }

    return best?.score ?? 0 > 0 ? best?.element : nil
}

public func isAXUIElement(_ value: Any) -> Bool {
    CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID()
}

public func valueContainsAXElement(_ value: Any) -> Bool {
    if isAXUIElement(value) {
        return true
    }
    if let values = value as? [Any] {
        return values.contains { valueContainsAXElement($0) }
    }
    return false
}

public func dedupeAXElements(_ elements: [AXUIElement]) -> [AXUIElement] {
    var seen = Set<String>()
    var out: [AXUIElement] = []
    for element in elements {
        let id = axElementID(element)
        guard !seen.contains(id) else {
            continue
        }
        seen.insert(id)
        out.append(element)
    }
    return out
}

public func axElementID(_ element: AXUIElement) -> String {
    String(describing: element)
}

public func sameAXElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
    CFEqual(lhs, rhs)
}

public func accessibilityTextLines(from value: Any) -> [String] {
    let textKeys = Set([
        "title",
        "value",
        "description",
        "help",
        "identifier",
        "selectedText",
        "placeholderValue",
        "roleDescription",
        "document",
        "filename",
        "url",
        "textContent",
        "visibleText",
        "path",
        "textPreview"
    ])
    var seen = Set<String>()
    var lines: [String] = []

    func visit(_ value: Any, key: String? = nil) {
        if let string = value as? String,
           let key,
           textKeys.contains(key) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !seen.contains(trimmed) {
                seen.insert(trimmed)
                lines.append(trimmed)
            }
            return
        }
        if let array = value as? [Any] {
            for item in array {
                visit(item)
            }
            return
        }
        if let object = value as? JSONObject {
            for (childKey, childValue) in object {
                visit(childValue, key: childKey)
            }
        }
    }

    visit(value)
    return lines
}

public func documentReferences(from value: Any, maxTextBytes: Int = 80_000) -> [JSONObject] {
    var seen = Set<String>()
    var paths: [String] = []

    func add(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let path: String?
        if trimmed.hasPrefix("file://") {
            path = URL(string: trimmed)?.path
        } else if trimmed.hasPrefix("/") {
            path = trimmed
        } else {
            path = nil
        }

        guard let path, !seen.contains(path) else {
            return
        }
        seen.insert(path)
        paths.append(path)
    }

    func visit(_ value: Any, key: String? = nil) {
        if let string = value as? String {
            if key == "document" || key == "filename" || key == "url" || string.hasPrefix("file://") {
                add(string)
            }
            return
        }
        if let array = value as? [Any] {
            for item in array {
                visit(item)
            }
            return
        }
        if let object = value as? JSONObject {
            for (childKey, childValue) in object {
                visit(childValue, key: childKey)
            }
        }
    }

    visit(value)

    return paths.map { path in
        var out: JSONObject = [
            "path": path,
            "url": URL(fileURLWithPath: path).absoluteString
        ]

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        out["exists"] = exists
        out["isDirectory"] = isDirectory.boolValue

        guard exists, !isDirectory.boolValue else {
            return out
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attributes[.size] as? NSNumber {
            out["sizeBytes"] = size.intValue
        }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            return out
        }
        defer {
            try? handle.close()
        }

        let data = handle.readData(ofLength: maxTextBytes + 1)
        let limited = data.prefix(maxTextBytes)
        if let text = String(data: limited, encoding: .utf8) {
            out["textPreview"] = text
            out["textPreviewBytes"] = limited.count
            out["textTruncated"] = data.count > maxTextBytes
        }
        return out
    }
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

public func copyAXParameterizedValue(_ element: AXUIElement, _ attribute: String, parameter: Any) -> Any? {
    AXUIElementSetMessagingTimeout(element, 0.25)
    var value: AnyObject?
    let result = AXUIElementCopyParameterizedAttributeValue(
        element,
        attribute as CFString,
        parameter as CFTypeRef,
        &value
    )
    guard result == .success else {
        return nil
    }
    return value
}

public func axParameterizedText(_ element: AXUIElement) -> String? {
    let visibleRange = copyAXValue(element, "AXVisibleCharacterRange").flatMap(axRange)
    let characterCount = copyAXValue(element, "AXNumberOfCharacters").flatMap(intValue)
    let range: CFRange?
    if let visibleRange, visibleRange.length > 0 {
        range = visibleRange
    } else if let characterCount, characterCount > 0 {
        range = CFRange(location: 0, length: min(characterCount, 20_000))
    } else {
        range = nil
    }

    guard let range,
          let parameter = axRangeValue(range),
          let value = copyAXParameterizedValue(element, "AXStringForRange", parameter: parameter) else {
        return nil
    }

    let text: String
    if let string = value as? String {
        text = string
    } else if let attributed = value as? NSAttributedString {
        text = attributed.string
    } else {
        text = String(describing: value)
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
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

public func axRange(_ value: Any) -> CFRange? {
    guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cfRange else {
        return nil
    }
    var range = CFRange()
    AXValueGetValue(axValue, .cfRange, &range)
    return range
}

public func axRangeValue(_ range: CFRange) -> AXValue? {
    var mutableRange = range
    return AXValueCreate(.cfRange, &mutableRange)
}

public func axRect(_ value: Any) -> CGRect? {
    guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgRect else {
        return nil
    }
    var rect = CGRect.zero
    AXValueGetValue(axValue, .cgRect, &rect)
    return rect
}

public func intValue(_ value: Any) -> Int? {
    switch value {
    case let number as NSNumber:
        return number.intValue
    case let int as Int:
        return int
    default:
        return nil
    }
}

public func numberValue(_ value: Any?) -> CGFloat? {
    switch value {
    case let number as NSNumber:
        return CGFloat(truncating: number)
    case let double as Double:
        return CGFloat(double)
    case let int as Int:
        return CGFloat(int)
    case let cgFloat as CGFloat:
        return cgFloat
    default:
        return nil
    }
}

public func jsonSafeAXValue(_ value: Any) -> Any? {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number
    case let array as [Any]:
        let values = array.compactMap(jsonSafeAXValue)
        return values.isEmpty && !array.isEmpty ? nil : values
    case let dictionary as [String: Any]:
        var out: JSONObject = [:]
        for (key, value) in dictionary {
            if let safeValue = jsonSafeAXValue(value) {
                out[key] = safeValue
            }
        }
        return out
    default:
        if let point = axPoint(value) {
            return ["x": point.x, "y": point.y]
        }
        if let size = axSize(value) {
            return ["width": size.width, "height": size.height]
        }
        if let rect = axRect(value) {
            return ["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height]
        }
        if let range = axRange(value) {
            return ["location": range.location, "length": range.length]
        }
        return nil
    }
}

public func jsonSafe(_ value: Any) -> Any {
    jsonSafeAXValue(value) ?? String(describing: value)
}

public func dedupeStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in values where !seen.contains(value) {
        seen.insert(value)
        out.append(value)
    }
    return out
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

// @sm:node appshot.ocr.snapshot
// @sm:feature appshot.capture
// @sm:prev appshot.core.capture
// @sm:next appshot.json.payload
// @sm:deps Vision,VNRecognizeTextRequest,screenshot
// @sm:evidence .build/debug/appshot capture --include-ocr --pretty
public func ocrSnapshot(
    screenshotPath: String?,
    screenshotCaptured: Bool,
    maxObservations: Int = 240
) -> JSONObject {
    guard let screenshotPath, !screenshotPath.isEmpty else {
        return [
            "available": false,
            "error": "OCR requires a screenshot path."
        ]
    }
    guard screenshotCaptured, FileManager.default.fileExists(atPath: screenshotPath) else {
        return [
            "available": false,
            "path": screenshotPath,
            "error": "OCR requires a successfully captured screenshot."
        ]
    }

    let url = URL(fileURLWithPath: screenshotPath)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

    let handler = VNImageRequestHandler(url: url, options: [:])
    do {
        try handler.perform([request])
    } catch {
        request.recognitionLanguages = []
        do {
            try handler.perform([request])
        } catch {
            return [
                "available": false,
                "path": screenshotPath,
                "error": String(describing: error)
            ]
        }
    }

    let observations = (request.results ?? [])
        .prefix(maxObservations)
        .compactMap { observation -> JSONObject? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            return [
                "text": candidate.string,
                "confidence": candidate.confidence,
                "boundingBox": [
                    "x": observation.boundingBox.origin.x,
                    "y": observation.boundingBox.origin.y,
                    "width": observation.boundingBox.size.width,
                    "height": observation.boundingBox.size.height
                ]
            ]
        }
    let text = observations
        .compactMap { $0["text"] as? String }
        .joined(separator: "\n")

    return [
        "available": true,
        "source": "Vision.VNRecognizeTextRequest",
        "path": screenshotPath,
        "observationCount": observations.count,
        "observationsTruncated": max(0, (request.results?.count ?? 0) - observations.count),
        "text": text,
        "observations": observations
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
