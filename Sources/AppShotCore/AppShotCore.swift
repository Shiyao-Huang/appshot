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
        accessibilityTimeoutSeconds: TimeInterval = 8.0,
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
        let frontmostApp = NSWorkspace.shared.frontmostApplication
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
            "frontmostApplication": appInfo(frontmostApp ?? app),
            "currentApplication": appInfo(app),
            "targetApplication": appInfo(app),
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
            payload["currentWindow"] = primaryWindow
            payload["frontmostWindow"] = primaryWindow
        } else {
            payload["primaryWindow"] = NSNull()
            payload["currentWindow"] = NSNull()
            payload["frontmostWindow"] = NSNull()
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
        payload["codex"] = codexSummaryPayload(from: payload)
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
            "screenRecording": screenCapture,
            "identity": permissionIdentity(),
            "stability": permissionStability()
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
        var advisories: [String] = []
        if !hasAccessibility {
            blockers.append("Accessibility permission is off; text/UI tree will be shallow.")
        }
        if !hasScreenRecording {
            blockers.append("Screen Recording permission is off; screenshots may fail.")
        }
        if let stability = permissionPayload["stability"] as? JSONObject,
           let warning = stability["warning"] as? String,
           !warning.isEmpty {
            advisories.append(warning)
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
            "blockers": blockers,
            "advisories": advisories,
            "frontmostApplication": NSNull(),
            "currentApplication": NSNull(),
            "primaryWindow": NSNull(),
            "frontmostWindow": NSNull(),
            "currentWindow": NSNull()
        ]

        if let frontmost {
            payload["frontmostApplication"] = appInfo(frontmost)
            payload["currentApplication"] = appInfo(frontmost)
        }
        if let primaryWindow {
            payload["primaryWindow"] = primaryWindow
            payload["frontmostWindow"] = primaryWindow
            payload["currentWindow"] = primaryWindow
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

public func permissionIdentity() -> JSONObject {
    let bundle = Bundle.main
    let executablePath = bundle.executableURL?.resolvingSymlinksInPath().path
        ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "").resolvingSymlinksInPath().path
    let bundlePath = bundle.bundleURL.resolvingSymlinksInPath().path
    let bundleIdentifier = bundle.bundleIdentifier ?? ""
    let isBundledApp = bundlePath.hasSuffix(".app")
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let recommendedAppPath = "\(home)/Applications/AppShot.app"
    let recommendedBundleIdentifier = recommendedAppBundleIdentifier(
        installedAppPath: recommendedAppPath,
        currentBundleIdentifier: isBundledApp ? bundleIdentifier : nil
    )

    return [
        "processIdentifier": ProcessInfo.processInfo.processIdentifier,
        "bundleIdentifier": bundleIdentifier,
        "bundlePath": bundlePath,
        "executablePath": executablePath,
        "isBundledApp": isBundledApp,
        "recommendedAppPath": recommendedAppPath,
        "recommendedBundleIdentifier": recommendedBundleIdentifier,
        "diagnosticScript": "scripts/diagnose_tcc_identity.sh"
    ]
}

private func recommendedAppBundleIdentifier(installedAppPath: String, currentBundleIdentifier: String?) -> String {
    if let currentBundleIdentifier, !currentBundleIdentifier.isEmpty {
        return currentBundleIdentifier
    }

    let infoPlistURL = URL(fileURLWithPath: installedAppPath)
        .appendingPathComponent("Contents")
        .appendingPathComponent("Info.plist")
    if let data = try? Data(contentsOf: infoPlistURL),
       let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
       let object = plist as? [String: Any],
       let bundleIdentifier = object["CFBundleIdentifier"] as? String,
       !bundleIdentifier.isEmpty {
        return bundleIdentifier
    }

    return "com.qppshot.AppShot"
}

public func permissionStability() -> JSONObject {
    let identity = permissionIdentity()
    let bundleIdentifier = identity["bundleIdentifier"] as? String ?? ""
    let bundlePath = identity["bundlePath"] as? String ?? ""
    let executablePath = identity["executablePath"] as? String ?? ""
    let recommendedAppPath = identity["recommendedAppPath"] as? String ?? ""
    let recommendedBundleIdentifier = identity["recommendedBundleIdentifier"] as? String ?? ""
    let isRecommendedApp = bundleIdentifier == recommendedBundleIdentifier && bundlePath == recommendedAppPath
    let isBundledApp = identity["isBundledApp"] as? Bool ?? false
    let isCommandLineTool = !isBundledApp

    var warning = ""
    var recoverySteps: [String] = []

    if isCommandLineTool {
        warning = "Permissions were checked by a command-line AppShot binary. macOS may store this separately from AppShot.app, so CLI/MCP permission state can differ from the installed app."
        recoverySteps = [
            "Use one fixed installed AppShot.app identity for prompting and manual grants.",
            "If System Settings already shows AppShot enabled but this binary reports false, run scripts/diagnose_tcc_identity.sh and check for CDHash drift.",
            "Reset stale rows once with tccutil reset Accessibility \(recommendedBundleIdentifier) and tccutil reset ScreenCapture \(recommendedBundleIdentifier), then open \(recommendedAppPath)."
        ]
    } else if !isRecommendedApp {
        warning = "Permissions were checked by an AppShot.app outside the recommended install path. Debug/rebuilt app bundles can have a different TCC identity from the installed app."
        recoverySteps = [
            "Install or open \(recommendedAppPath), then grant Accessibility and Screen Recording to that app.",
            "Avoid switching between Debug, release, and installed AppShot.app when validating permissions."
        ]
    }

    return [
        "mode": isRecommendedApp ? "stableInstalledApp" : isCommandLineTool ? "commandLineTool" : "alternateAppBundle",
        "isStableGrantTarget": isRecommendedApp,
        "warning": warning,
        "recommendedGrantTarget": [
            "bundleIdentifier": recommendedBundleIdentifier,
            "path": recommendedAppPath
        ],
        "recoverySteps": recoverySteps,
        "currentExecutablePath": executablePath
    ]
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
            "windowNumber": info[kCGWindowNumber as String] as? UInt32 ?? 0,
            "ownerPID": ownerPID,
            "ownerName": info[kCGWindowOwnerName as String] as? String ?? "",
            "title": info[kCGWindowName as String] as? String ?? "",
            "layer": layer,
            "alpha": info[kCGWindowAlpha as String] as? Double ?? 0,
            "isOnScreen": true
        ]

        if let bounds = info[kCGWindowBounds as String] as? JSONObject {
            out["bounds"] = normalizedBounds(bounds)
            if let width = bounds["Width"] as? CGFloat, let height = bounds["Height"] as? CGFloat {
                out["area"] = width * height
            }
            if let screen = screenForWindowBounds(bounds) {
                out["screen"] = screen
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

public func screenForWindowBounds(_ bounds: JSONObject) -> JSONObject? {
    guard let x = numberValue(bounds["X"]),
          let y = numberValue(bounds["Y"]),
          let width = numberValue(bounds["Width"]),
          let height = numberValue(bounds["Height"]) else {
        return nil
    }

    let windowRect = CGRect(x: x, y: y, width: width, height: height)
    let displayMatches = activeDisplays()
        .map { display -> (display: CGDirectDisplayID, bounds: CGRect, intersectionArea: CGFloat) in
            let bounds = CGDisplayBounds(display)
            let intersection = bounds.intersection(windowRect)
            return (display, bounds, intersection.width * intersection.height)
        }
        .sorted { $0.intersectionArea > $1.intersectionArea }

    if let best = displayMatches.first,
       best.intersectionArea > 0 {
        return [
            "displayID": best.display,
            "frame": rectPayload(best.bounds),
            "isMain": best.display == CGMainDisplayID()
        ]
    }

    let screenMatches = NSScreen.screens
        .map { screen -> (screen: NSScreen, intersectionArea: CGFloat) in
            let intersection = screen.frame.intersection(windowRect)
            return (screen, intersection.width * intersection.height)
        }
        .sorted { $0.intersectionArea > $1.intersectionArea }

    guard let best = screenMatches.first,
          best.intersectionArea > 0 else {
        return nil
    }

    return [
        "localizedName": best.screen.localizedName,
        "frame": rectPayload(best.screen.frame),
        "visibleFrame": rectPayload(best.screen.visibleFrame),
        "backingScaleFactor": best.screen.backingScaleFactor
    ]
}

public func activeDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success,
          count > 0 else {
        return []
    }

    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
        return []
    }
    return Array(displays.prefix(Int(count)))
}

public func rectPayload(_ rect: CGRect) -> JSONObject {
    [
        "x": rect.origin.x,
        "y": rect.origin.y,
        "width": rect.size.width,
        "height": rect.size.height
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
    AXUIElementSetMessagingTimeout(appElement, 0.75)
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
    let focusedAXWindow = focusedWindowResult == .success ? axElement(from: focusedWindow) : nil
    let mainAXWindow = mainWindowResult == .success ? axElement(from: mainWindow) : nil
    let windowFallback = [focusedAXWindow, mainAXWindow].compactMap { $0 }.first(where: axIsWindowElement)
    let rootElement = targetAXWindow ?? windowFallback ?? appElement
    let rootSource = targetAXWindow != nil ? "targetWindow" : windowFallback != nil ? "focusedWindow" : "application"
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
        "rootSource": rootSource,
        "root": root
    ]

    if let targetWindow {
        payload["targetWindow"] = targetWindow
    }

    if focusedElementResult == .success,
       let focusedElement {
        let focusedAXElement = focusedElement as! AXUIElement
        if !sameAXElement(focusedAXElement, rootElement) {
            var focusedVisited = Set<String>()
            payload["focusedElement"] = elementSnapshot(
                focusedAXElement,
                depth: 0,
                maxDepth: max(1, min(maxDepth, 4)),
                maxChildren: maxChildren,
                deadline: deadline,
                visited: &focusedVisited
            )
        }
    }

    if mainWindowResult == .success,
       let mainWindow {
        let mainAXWindow = mainWindow as! AXUIElement
        if !sameAXElement(mainAXWindow, rootElement) {
            var mainWindowVisited = Set<String>()
            payload["mainWindow"] = elementSnapshot(
                mainAXWindow,
                depth: 0,
                maxDepth: max(1, min(maxDepth, 4)),
                maxChildren: maxChildren,
                deadline: deadline,
                visited: &mainWindowVisited
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
    let visibleLines = visibleTextLines(from: payload)
    payload["visibleText"] = visibleLines.joined(separator: "\n")
    payload["visibleTextLineCount"] = visibleLines.count

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

    AXUIElementSetMessagingTimeout(element, depth <= 2 ? 0.75 : 0.35)
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
        kAXEnabledAttribute,
        kAXSelectedTextAttribute,
        "AXFocused",
        "AXSelected",
        "AXPlaceholderValue",
        "AXRoleDescription",
        "AXDocument",
        "AXFilename",
        "AXURL"
    ]
    let attributes = dedupeStrings(fixedAttributes + (depth <= 1 ? axAttributeNames(element) : []))
    var discoveredChildAttributes: [String] = []

    for attribute in attributes {
        if let value = copyAXValue(element, attribute) {
            if valueContainsAXElement(value) {
                if isAXDescendantAttribute(attribute) {
                    discoveredChildAttributes.append(attribute)
                }
            } else if let safeValue = jsonSafeAXValue(value) {
                out[attribute.replacingOccurrences(of: "AX", with: "").lowercasedFirst] = safeValue
            }
        }
    }
    if axShouldProbeSettableAttributes(out) {
        let settableAttributes = axSettableAttributes(element)
        if !settableAttributes.isEmpty {
            out["settableAttributes"] = settableAttributes
        }
    }

    if axShouldProbeParameterizedText(out),
       let parameterizedText = axParameterizedText(element) {
        out["textContent"] = parameterizedText.text
        let fragments = axParameterizedTextFragments(
            element,
            text: parameterizedText.text,
            range: parameterizedText.range
        )
        if !fragments.isEmpty {
            out["visibleTextFragments"] = fragments
        }
    }

    if axShouldCompactRow(out) {
        for (key, value) in axFirstDescendantTextPayload(element, deadline: deadline, remainingDepth: 3) {
            if out[key] == nil {
                out[key] = value
            }
        }
        let controls = axCompactInteractiveDescendants(
            element,
            depth: depth,
            maxChildren: maxChildren,
            deadline: deadline,
            visited: &visited
        )
        if !controls.isEmpty {
            out["children"] = controls
        }
        return out
    }

    if axShouldCaptureGeometry(out, depth: depth) {
        if let position = copyAXValue(element, kAXPositionAttribute),
           let point = axPoint(position) {
            out["position"] = ["x": point.x, "y": point.y]
        }
        if let size = copyAXValue(element, kAXSizeAttribute),
           let cgSize = axSize(size) {
            out["size"] = ["width": cgSize.width, "height": cgSize.height]
        }
    }

    guard depth < maxDepth, axShouldSnapshotChildren(out) else {
        return out
    }

    let childMaxDepth = axChildMaxDepth(parentSnapshot: out, parentDepth: depth, requestedMaxDepth: maxDepth)
    let childAttributes = axPreferredChildAttributes(parentSnapshot: out, discovered: discoveredChildAttributes)

    var localChildIDs = Set<String>()
    for childAttribute in dedupeStrings(childAttributes) {
        guard Date() < deadline else {
            out["truncatedByTimeout"] = true
            return out
        }

        let children = axChildElements(element, attribute: childAttribute).filter { child in
            let childID = axElementID(child)
            guard !localChildIDs.contains(childID) else {
                return false
            }
            localChildIDs.insert(childID)
            return true
        }
        guard !children.isEmpty else {
            continue
        }

        let key = childAttribute.replacingOccurrences(of: "AX", with: "").lowercasedFirst
        let limited = Array(children.prefix(maxChildren))
        out[key] = limited.map {
            elementSnapshot(
                $0,
                depth: depth + 1,
                maxDepth: childMaxDepth,
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
    "AXSplitters"
]

public func isAXDescendantAttribute(_ attribute: String) -> Bool {
    Set(axChildAttributes).contains(attribute)
}

private func axPreferredChildAttributes(parentSnapshot: JSONObject, discovered: [String]) -> [String] {
    let role = parentSnapshot["role"] as? String
    switch role {
    case "AXCell", "AXRow", "AXOutlineRow":
        return [kAXChildrenAttribute]
    case "AXList", "AXOutline", "AXTable":
        return [
            "AXVisibleRows",
            "AXRows",
            kAXChildrenAttribute
        ]
    case "AXScrollArea":
        return [
            "AXContents",
            kAXChildrenAttribute,
            "AXVisibleChildren"
        ]
    case "AXSplitGroup":
        return [
            kAXChildrenAttribute,
            "AXSplitters"
        ]
    case "AXWindow", "AXGroup", "AXToolbar":
        return [
            kAXChildrenAttribute,
            "AXContents",
            "AXTabs",
            "AXSplitters"
        ]
    default:
        return dedupeStrings(discovered + axChildAttributes)
    }
}

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

public func axSettableAttributes(_ element: AXUIElement) -> [String] {
    let attributes = [
        kAXValueAttribute,
        kAXFocusedAttribute,
        kAXSelectedTextAttribute,
        kAXSelectedChildrenAttribute,
        kAXSelectedRowsAttribute,
        kAXPositionAttribute,
        kAXSizeAttribute
    ].map { $0 as String }

    return attributes.compactMap { attribute in
        var isSettable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &isSettable)
        guard result == .success, isSettable.boolValue else {
            return nil
        }
        return attribute.replacingOccurrences(of: "AX", with: "").lowercasedFirst
    }
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

private func axShouldProbeSettableAttributes(_ snapshot: JSONObject) -> Bool {
    let role = snapshot["role"] as? String
    let roleDescription = snapshot["roleDescription"] as? String
    let probeRoles = Set([
        "AXScrollBar",
        "AXSlider",
        "AXSplitter",
        "AXTextArea",
        "AXTextField"
    ])

    if let role, probeRoles.contains(role) {
        return true
    }
    if roleDescription?.contains("文本栏") == true || roleDescription?.contains("滚动条") == true {
        return true
    }
    return false
}

private func axShouldCaptureGeometry(_ snapshot: JSONObject, depth: Int) -> Bool {
    if depth <= 1 {
        return true
    }
    switch snapshot["role"] as? String {
    case "AXScrollBar",
         "AXSplitter",
         "AXStaticText",
         "AXTextArea",
         "AXTextField",
         "AXValueIndicator",
         "AXWindow":
        return true
    default:
        return false
    }
}

private func axShouldCompactRow(_ snapshot: JSONObject) -> Bool {
    switch snapshot["role"] as? String {
    case "AXRow", "AXOutlineRow":
        return true
    default:
        return false
    }
}

private func axShouldSnapshotChildren(_ snapshot: JSONObject) -> Bool {
    switch snapshot["role"] as? String {
    case "AXButton",
         "AXCheckBox",
         "AXImage",
         "AXMenuButton",
         "AXPopUpButton",
         "AXRadioButton",
         "AXScrollBar",
         "AXSlider",
         "AXStaticText",
         "AXSwitch",
         "AXTextArea",
         "AXTextField":
        return false
    default:
        return true
    }
}

private func axFirstDescendantTextPayload(
    _ element: AXUIElement,
    deadline: Date,
    remainingDepth: Int
) -> JSONObject {
    guard Date() < deadline, remainingDepth >= 0 else {
        return [:]
    }

    let role = copyAXValue(element, kAXRoleAttribute) as? String
    let title = (copyAXValue(element, kAXTitleAttribute) as? String)
        .flatMap(codexTrimmedString)
    let description = (copyAXValue(element, kAXDescriptionAttribute) as? String)
        .flatMap(codexTrimmedString)
    let value = (copyAXValue(element, kAXValueAttribute) as? String)
        .flatMap(codexTrimmedString)

    if role == "AXStaticText" || role == "AXTextField" || role == "AXTextArea" {
        if let description {
            var out: JSONObject = ["description": description]
            if let value {
                out["value"] = value
            }
            return out
        }
        if let value {
            return ["value": value, "textContent": value]
        }
        if let title {
            return ["title": title]
        }
    }

    guard remainingDepth > 0 else {
        return [:]
    }

    for attribute in [kAXChildrenAttribute as String, "AXVisibleChildren"] {
        for child in axChildElements(element, attribute: attribute) {
            let payload = axFirstDescendantTextPayload(
                child,
                deadline: deadline,
                remainingDepth: remainingDepth - 1
            )
            if !payload.isEmpty {
                return payload
            }
        }
    }
    return [:]
}

private func axCompactInteractiveDescendants(
    _ element: AXUIElement,
    depth: Int,
    maxChildren: Int,
    deadline: Date,
    visited: inout Set<String>
) -> [JSONObject] {
    var controls: [JSONObject] = []

    func visit(_ candidate: AXUIElement, remainingDepth: Int) {
        guard Date() < deadline,
              remainingDepth >= 0,
              controls.count < maxChildren else {
            return
        }

        if let role = copyAXValue(candidate, kAXRoleAttribute) as? String,
           axIsCompactInteractiveRole(role) {
            controls.append(elementSnapshot(
                candidate,
                depth: depth + 1,
                maxDepth: depth + 1,
                maxChildren: maxChildren,
                deadline: deadline,
                visited: &visited
            ))
            return
        }

        guard remainingDepth > 0 else {
            return
        }
        for attribute in [kAXChildrenAttribute as String, "AXVisibleChildren"] {
            for child in axChildElements(candidate, attribute: attribute) {
                visit(child, remainingDepth: remainingDepth - 1)
            }
        }
    }

    for attribute in [kAXChildrenAttribute as String, "AXVisibleChildren"] {
        for child in axChildElements(element, attribute: attribute) {
            visit(child, remainingDepth: 3)
        }
    }
    return controls
}

private func axIsCompactInteractiveRole(_ role: String) -> Bool {
    switch role {
    case "AXButton", "AXCheckBox", "AXMenuButton", "AXPopUpButton", "AXRadioButton", "AXSlider", "AXSwitch":
        return true
    default:
        return false
    }
}

private func axShouldProbeParameterizedText(_ snapshot: JSONObject) -> Bool {
    switch snapshot["role"] as? String {
    case "AXTextArea", "AXTextField":
        return true
    default:
        break
    }
    let roleDescription = snapshot["roleDescription"] as? String ?? ""
    return roleDescription == "text area"
        || roleDescription == "text field"
        || roleDescription == "文本区域"
        || roleDescription == "文本栏"
        || roleDescription == "搜索文本栏"
}

private func axChildMaxDepth(parentSnapshot: JSONObject, parentDepth: Int, requestedMaxDepth: Int) -> Int {
    switch parentSnapshot["role"] as? String {
    case "AXRow", "AXOutlineRow":
        return min(requestedMaxDepth, parentDepth + 3)
    case "AXCell":
        return min(requestedMaxDepth, parentDepth + 2)
    default:
        return requestedMaxDepth
    }
}

public func matchingAXWindow(appElement: AXUIElement, targetWindow: JSONObject) -> AXUIElement? {
    var focusedWindow: AnyObject?
    let focusedWindowResult = AXUIElementCopyAttributeValue(
        appElement,
        kAXFocusedWindowAttribute as CFString,
        &focusedWindow
    )
    var mainWindow: AnyObject?
    let mainWindowResult = AXUIElementCopyAttributeValue(
        appElement,
        kAXMainWindowAttribute as CFString,
        &mainWindow
    )
    var candidates: [AXUIElement] = []
    if focusedWindowResult == .success, let focusedWindow {
        candidates.append(focusedWindow as! AXUIElement)
    }
    if mainWindowResult == .success, let mainWindow {
        candidates.append(mainWindow as! AXUIElement)
    }
    candidates +=
        axChildElements(appElement, attribute: kAXWindowsAttribute) +
        axChildElements(appElement, attribute: "AXVisibleChildren") +
        axChildElements(appElement, attribute: kAXChildrenAttribute)
    let windows = dedupeAXElements(
        candidates
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

private func axIsWindowElement(_ element: AXUIElement) -> Bool {
    (copyAXValue(element, kAXRoleAttribute) as? String) == "AXWindow"
}

public func isAXUIElement(_ value: Any) -> Bool {
    CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID()
}

private func axElement(from value: AnyObject?) -> AXUIElement? {
    guard let value, isAXUIElement(value) else {
        return nil
    }
    return (value as! AXUIElement)
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
    var parts = [String(describing: element)]
    for attribute in [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXIdentifierAttribute,
        kAXTitleAttribute,
        kAXDescriptionAttribute,
        kAXRoleDescriptionAttribute
    ] {
        if let value = copyAXValue(element, attribute),
           let safeValue = jsonSafeAXValue(value) {
            parts.append("\(attribute)=\(safeValue)")
        }
    }
    if let position = copyAXValue(element, kAXPositionAttribute),
       let point = axPoint(position) {
        parts.append("position=\(Int(point.x)),\(Int(point.y))")
    }
    if let size = copyAXValue(element, kAXSizeAttribute),
       let cgSize = axSize(size) {
        parts.append("size=\(Int(cgSize.width))x\(Int(cgSize.height))")
    }
    return parts.joined(separator: "|")
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

public struct VisibleTextEntry {
    public let text: String
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat
}

public struct AXParameterizedText {
    public let text: String
    public let range: CFRange
}

public func visibleTextLines(from value: Any) -> [String] {
    let visibleTextKeys = [
        "textContent",
        "selectedText",
        "value",
        "title",
        "description",
        "placeholderValue",
        "help"
    ]
    var entries: [VisibleTextEntry] = []

    func textFragments(from raw: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> [VisibleTextEntry] {
        let fragments = raw
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !fragments.isEmpty else {
            return []
        }

        let lineHeight = fragments.count > 1 && height > 0
            ? max(1, height / CGFloat(fragments.count))
            : height
        return fragments.enumerated().map { index, text in
            VisibleTextEntry(
                text: text,
                x: x,
                y: y + CGFloat(index) * lineHeight,
                width: width,
                height: lineHeight
            )
        }
    }

    func visit(_ value: Any) {
        if let array = value as? [Any] {
            for item in array {
                visit(item)
            }
            return
        }

        guard let object = value as? JSONObject else {
            return
        }

        if let fragments = object["visibleTextFragments"] as? [JSONObject] {
            for fragment in fragments {
                guard let text = fragment["text"] as? String,
                      let position = fragment["position"] as? JSONObject,
                      let size = fragment["size"] as? JSONObject,
                      let x = numberValue(position["x"]),
                      let y = numberValue(position["y"]),
                      let width = numberValue(size["width"]),
                      let height = numberValue(size["height"]) else {
                    continue
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    continue
                }
                entries.append(VisibleTextEntry(text: trimmed, x: x, y: y, width: width, height: height))
            }
        }

        if let position = object["position"] as? JSONObject,
           let size = object["size"] as? JSONObject,
           let x = numberValue(position["x"]),
           let y = numberValue(position["y"]),
           let width = numberValue(size["width"]),
           let height = numberValue(size["height"]),
           width > 0,
           height > 0 {
            for key in visibleTextKeys {
                guard let raw = object[key] as? String else {
                    continue
                }
                entries.append(contentsOf: textFragments(from: raw, x: x, y: y, width: width, height: height))
            }
        }

        for child in object.values {
            if child is JSONObject || child is [Any] {
                visit(child)
            }
        }
    }

    visit(value)

    var seen = Set<String>()
    let sorted = entries.sorted {
        let yDelta = abs($0.y - $1.y)
        if yDelta > 8 {
            return $0.y < $1.y
        }
        if abs($0.x - $1.x) > 8 {
            return $0.x < $1.x
        }
        return $0.text < $1.text
    }

    var lines: [String] = []
    for entry in sorted {
        let key = "\(entry.text)|\(Int(entry.x / 4))|\(Int(entry.y / 4))"
        guard !seen.contains(key) else {
            continue
        }
        seen.insert(key)
        lines.append(entry.text)
    }
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

public func axParameterizedText(_ element: AXUIElement) -> AXParameterizedText? {
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
    return trimmed.isEmpty ? nil : AXParameterizedText(text: trimmed, range: range)
}

public func axParameterizedTextFragments(
    _ element: AXUIElement,
    text: String,
    range: CFRange,
    maxLines: Int = 400
) -> [JSONObject] {
    let nsText = text as NSString
    var fragments: [JSONObject] = []
    var location = 0

    while location < nsText.length && fragments.count < maxLines {
        let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
        var contentLength = lineRange.length
        while contentLength > 0 {
            let char = nsText.character(at: lineRange.location + contentLength - 1)
            if char == 10 || char == 13 {
                contentLength -= 1
            } else {
                break
            }
        }

        let contentRange = NSRange(location: lineRange.location, length: contentLength)
        let rawLine = contentLength > 0 ? nsText.substring(with: contentRange) : ""
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let axRange = CFRange(location: range.location + contentRange.location, length: max(1, contentRange.length))
            if let parameter = axRangeValue(axRange),
               let value = copyAXParameterizedValue(element, "AXBoundsForRange", parameter: parameter),
               let rect = axRect(value),
               rect.width > 0,
               rect.height > 0 {
                fragments.append([
                    "text": trimmed,
                    "position": ["x": rect.origin.x, "y": rect.origin.y],
                    "size": ["width": rect.size.width, "height": rect.size.height],
                    "range": ["location": axRange.location, "length": axRange.length]
                ])
            }
        }

        let nextLocation = lineRange.location + max(lineRange.length, 1)
        if nextLocation <= location {
            break
        }
        location = nextLocation
    }

    if location < nsText.length {
        fragments.append([
            "text": "[visible text truncated]",
            "position": ["x": 0, "y": CGFloat.greatestFiniteMagnitude],
            "size": ["width": 1, "height": 1],
            "truncated": true
        ])
    }
    return fragments
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

public func codexSummaryPayload(from payload: JSONObject, maxTreeLines: Int = 420) -> JSONObject {
    let text = codexSummaryText(from: payload, maxTreeLines: maxTreeLines)
    let accessibility = payload["accessibility"] as? JSONObject
    let root = accessibility?["root"] as? JSONObject
    let selectedLines = codexSelectedElementLines(from: root)
    let focusedLine = codexFocusedElementLine(from: accessibility)

    return [
        "format": "codex-appshot-text",
        "text": text,
        "treeLineCount": codexTreeLines(from: root, maxLines: maxTreeLines).count,
        "selectedLineCount": selectedLines.count,
        "hasFocusedElement": focusedLine != nil
    ]
}

public func codexSummaryText(from payload: JSONObject, maxTreeLines: Int = 420) -> String {
    let app = payload["targetApplication"] as? JSONObject
        ?? payload["currentApplication"] as? JSONObject
        ?? payload["frontmostApplication"] as? JSONObject
        ?? [:]
    let window = payload["primaryWindow"] as? JSONObject
        ?? payload["currentWindow"] as? JSONObject
        ?? payload["frontmostWindow"] as? JSONObject
    let accessibility = payload["accessibility"] as? JSONObject
    let root = accessibility?["root"] as? JSONObject
    let screenshot = payload["screenshot"] as? JSONObject

    let appName = codexTrimmedString(app["localizedName"]) ?? codexTrimmedString(app["bundleIdentifier"]) ?? "Unknown"
    let bundleIdentifier = codexTrimmedString(app["bundleIdentifier"]) ?? ""
    let windowTitle = codexTrimmedString(window?["title"]) ?? codexTrimmedString(root?["title"]) ?? appName
    let imagePath = codexTrimmedString(screenshot?["path"]) ?? ""

    var attributes = [
        "app=\"\(codexEscapeAttribute(appName))\"",
        "bundle-identifier=\"\(codexEscapeAttribute(bundleIdentifier))\"",
        "window-title=\"\(codexEscapeAttribute(windowTitle))\""
    ]
    if !imagePath.isEmpty {
        attributes.append("image=\"\(codexEscapeAttribute(imagePath))\"")
    }

    var lines: [String] = [
        "<appshot \(attributes.joined(separator: " "))>",
        "Window: \"\(windowTitle)\", App: \(appName)."
    ]

    let treeLines = codexTreeLines(from: root, maxLines: maxTreeLines)
    if treeLines.isEmpty {
        lines.append("No accessibility tree was captured.")
    } else {
        lines.append(contentsOf: treeLines)
    }

    let selectedLines = codexSelectedElementLines(from: root)
    if !selectedLines.isEmpty {
        lines.append("")
        lines.append("Selected:")
        lines.append(contentsOf: selectedLines.map { "\t\($0)" })
        lines.append("")
        lines.append("Note: Pay special attention to the content selected by the user. If the user asks a question or refers to the content they are looking at on-screen, they might be referring to the selected content (but they might be referring to something else that's visible, too).")
    }

    if let focusedLine = codexFocusedElementLine(from: accessibility),
       focusedLine != codexElementLine(root ?? [:]) {
        lines.append("")
        lines.append("The focused UI element is \(focusedLine)")
    }

    let visibleText = codexTrimmedString(accessibility?["visibleText"])
    let text = codexTrimmedString(accessibility?["text"])
    if visibleText == nil, let text {
        let preview = text.split(separator: "\n").prefix(12).joined(separator: "\n")
        if !preview.isEmpty {
            lines.append("")
            lines.append("Text:")
            lines.append(preview)
        }
    }

    lines.append("</appshot>")
    return lines.joined(separator: "\n")
}

private func codexTreeLines(from root: JSONObject?, maxLines: Int) -> [String] {
    guard let root else {
        return []
    }

    var lines: [String] = []
    var seen = Set<String>()
    codexAppendElementLines(root, depth: 0, lines: &lines, maxLines: maxLines, seen: &seen)
    return lines
}

private func codexAppendElementLines(_ element: JSONObject, depth: Int, lines: inout [String], maxLines: Int, seen: inout Set<String>) {
    guard lines.count < maxLines else {
        return
    }

    let digest = codexElementDigest(element)
    let includeLine = codexShouldIncludeElementLine(element) && !seen.contains(digest)
    if includeLine {
        seen.insert(digest)
        lines.append(String(repeating: "\t", count: depth) + codexElementLine(element))
    }

    let children = codexChildrenForSummary(of: element)
    for child in children {
        guard lines.count < maxLines else {
            lines.append(String(repeating: "\t", count: includeLine ? depth + 1 : depth) + "... truncated")
            return
        }
        codexAppendElementLines(child, depth: includeLine ? depth + 1 : depth, lines: &lines, maxLines: maxLines, seen: &seen)
    }
}

private func codexSelectedElementLines(from root: JSONObject?) -> [String] {
    guard let root else {
        return []
    }

    var lines: [String] = []
    codexVisitElements(root) { element in
        if codexIsSelected(element) {
            lines.append(codexElementLine(element))
        }
    }
    return Array(lines.prefix(40))
}

private func codexFocusedElementLine(from accessibility: JSONObject?) -> String? {
    if let focused = accessibility?["focusedElement"] as? JSONObject {
        guard codexShouldIncludeElementLine(focused) else {
            return nil
        }
        return codexElementLine(focused)
    }

    if let root = accessibility?["root"] as? JSONObject {
        var focusedLine: String?
        codexVisitElements(root) { element in
            if focusedLine == nil,
               element["focused"] as? Bool == true,
               codexShouldIncludeElementLine(element) {
                focusedLine = codexElementLine(element)
            }
        }
        return focusedLine
    }

    return nil
}

private func codexVisitElements(_ element: JSONObject, _ visit: (JSONObject) -> Void) {
    visit(element)
    for child in codexSemanticChildren(of: element) {
        codexVisitElements(child, visit)
    }
}

private func codexElementLine(_ element: JSONObject) -> String {
    let role = codexRoleName(element)
    var parts: [String] = []

    parts.append(role)
    if codexIsSelected(element) {
        parts.append("(selected)")
    }

    let title = codexTrimmedString(element["title"])
    let description = codexTrimmedString(element["description"])
    let value = codexTrimmedString(element["value"])
    let textContent = codexTrimmedString(element["textContent"])
    let placeholder = codexTrimmedString(element["placeholderValue"])
    let identifier = codexTrimmedString(element["identifier"])
    let selectedText = codexTrimmedString(element["selectedText"])

    let descendantLabel = ["row", "cell"].contains(role)
        ? codexPrimaryDescendantLabel(element)
        : nil
    let settableAnnotation = codexSettableAnnotation(element)

    if let settableAnnotation {
        parts.append(settableAnnotation)
    }

    if let title {
        parts.append(title)
    } else if role == "text",
              let text = value ?? textContent ?? description {
        parts.append(text)
    } else if let description {
        parts.append(codexDescriptionLabel(description, role: role))
    } else if let textContent {
        parts.append(textContent)
    } else if let descendantLabel {
        parts.append(descendantLabel)
    }

    if role != "text",
       settableAnnotation == nil,
       let value,
       value != title,
       value != description,
       value != textContent {
        parts.append("Value: \(value)")
    }
    if let placeholder,
       settableAnnotation == nil || placeholder != codexSettableValueString(element) {
        parts.append("Placeholder: \(placeholder)")
    }
    if let selectedText, selectedText != title, selectedText != value {
        parts.append("SelectedText: \(selectedText)")
    }
    if let identifier,
       codexShouldRenderIdentifier(identifier, role: role) {
        if codexIdentifierShouldBeRaw(identifier, role: role) {
            parts.append(identifier)
        } else if parts.count > 1, let last = parts.popLast() {
            parts.append("\(last), ID: \(identifier)")
        } else {
            parts.append("ID: \(identifier)")
        }
    }

    if let truncated = element["truncated"] as? Int, truncated > 0 {
        parts.append("children truncated: \(truncated)")
    }
    return parts.joined(separator: " ")
}

private func codexDescriptionLabel(_ description: String, role: String) -> String {
    let rawDescriptionRoles = Set([
        "list",
        "outline",
        "scroll area",
        "split group",
        "toolbar",
        "列表",
        "大纲",
        "滚动区",
        "分离组",
        "工具栏"
    ])
    if rawDescriptionRoles.contains(role) {
        return description
    }
    return "Description: \(description)"
}

private func codexIdentifierShouldBeRaw(_ identifier: String, role: String) -> Bool {
    if ["split group", "分离组"].contains(role) {
        return true
    }
    return identifier.contains(",") && !["standard window", "标准窗口", "window"].contains(role)
}

private func codexShouldRenderIdentifier(_ identifier: String, role: String) -> Bool {
    if identifier.isEmpty {
        return false
    }
    let hiddenControlRoles = Set([
        "button",
        "checkbox",
        "menu button",
        "pop up button",
        "radio button",
        "switch",
        "按钮",
        "复选框",
        "菜单按钮",
        "弹出式按钮",
        "单选按钮",
        "转换"
    ])
    return !hiddenControlRoles.contains(role)
}

private func codexSettableAnnotation(_ element: JSONObject) -> String? {
    guard let attributes = element["settableAttributes"] as? [String],
          attributes.contains("value") else {
        return nil
    }

    guard let rawValue = codexSettableRawValue(element) else {
        return nil
    }

    return "(settable, \(codexValueTypeName(rawValue))) \(codexScalarString(rawValue))"
}

private func codexSettableRawValue(_ element: JSONObject) -> Any? {
    if let value = element["value"] {
        if let string = value as? String {
            if let trimmed = codexTrimmedString(string) {
                return trimmed
            }
        } else {
            return value
        }
    }
    return element["placeholderValue"]
}

private func codexSettableValueString(_ element: JSONObject) -> String? {
    guard let rawValue = codexSettableRawValue(element) else {
        return nil
    }
    return codexScalarString(rawValue)
}

private func codexValueTypeName(_ value: Any) -> String {
    if value is Bool {
        return "bool"
    }
    if value is String {
        return "string"
    }
    if value is Int || value is Double || value is Float || value is CGFloat || value is NSNumber {
        return "float"
    }
    return "value"
}

private func codexScalarString(_ value: Any) -> String {
    if let string = value as? String {
        return string
    }
    if let bool = value as? Bool {
        return bool ? "1" : "0"
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return String(describing: value)
}

private func codexShouldIncludeElementLine(_ element: JSONObject) -> Bool {
    if codexIsColumn(element) {
        return false
    }

    if codexTrimmedString(element["role"]) == nil,
       codexTrimmedString(element["roleDescription"]) == nil,
       codexTrimmedString(element["title"]) == nil,
       codexTrimmedString(element["description"]) == nil,
       codexTrimmedString(element["value"]) == nil,
       codexTrimmedString(element["identifier"]) == nil,
       element["truncatedByTimeout"] as? Bool == true {
        return false
    }

    let role = codexRoleName(element)
    if ["element", "组", "group", "cell"].contains(role),
        codexTrimmedString(element["title"]) == nil,
       codexTrimmedString(element["description"]) == nil,
       codexTrimmedString(element["value"]) == nil,
       codexTrimmedString(element["textContent"]) == nil,
       codexTrimmedString(element["identifier"]) == nil,
       !codexIsSelected(element) {
        let childCount = codexSemanticChildren(of: element).count
        return childCount != 1
    }

    return true
}

private let codexChildKeys = [
    "windows",
    "children",
    "visibleChildren",
    "selectedChildren",
    "contents",
    "rows",
    "visibleRows",
    "columns",
    "visibleColumns",
    "tabs",
    "childrenInNavigationOrder",
    "splitters"
]

private func codexSemanticChildren(of element: JSONObject) -> [JSONObject] {
    for key in ["visibleRows", "rows", "children", "childrenInNavigationOrder", "selectedChildren", "visibleChildren", "contents", "tabs", "splitters", "windows"] {
        if let children = element[key] as? [JSONObject], !children.isEmpty {
            let semanticChildren = children.filter { !codexIsColumn($0) && !codexIsWindowChromeElement($0) }
            if !semanticChildren.isEmpty {
                return semanticChildren
            }
        }
    }
    return []
}

private func codexChildrenForSummary(of element: JSONObject) -> [JSONObject] {
    if codexRoleName(element) == "row" {
        return codexInteractiveDescendants(of: element)
    }
    return codexSemanticChildren(of: element)
}

private func codexInteractiveDescendants(of element: JSONObject) -> [JSONObject] {
    var controls: [JSONObject] = []

    func visit(_ value: JSONObject) {
        if codexIsInteractiveControl(value) {
            controls.append(value)
            return
        }
        for child in codexSemanticChildren(of: value) {
            visit(child)
        }
    }

    for child in codexSemanticChildren(of: element) {
        visit(child)
    }
    return controls
}

private func codexIsInteractiveControl(_ element: JSONObject) -> Bool {
    switch codexTrimmedString(element["role"]) {
    case "AXButton", "AXCheckBox", "AXSwitch", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTextField", "AXSlider":
        return true
    default:
        return false
    }
}

private func codexIsColumn(_ element: JSONObject) -> Bool {
    codexTrimmedString(element["role"]) == "AXColumn" || codexTrimmedString(element["roleDescription"]) == "栏"
}

private func codexIsWindowChromeElement(_ element: JSONObject) -> Bool {
    guard codexTrimmedString(element["role"]) == "AXButton",
          let roleDescription = codexTrimmedString(element["roleDescription"]) else {
        return false
    }
    let chromeDescriptions = Set([
        "close button",
        "full screen button",
        "minimize button",
        "zoom button",
        "关闭按钮",
        "全屏幕按钮",
        "最小化按钮",
        "缩放按钮"
    ])
    return chromeDescriptions.contains(roleDescription)
}

private func codexPrimaryDescendantLabel(_ element: JSONObject) -> String? {
    var found: String?
    func visit(_ value: JSONObject) {
        guard found == nil else {
            return
        }
        if let title = codexTrimmedString(value["title"]) {
            found = title
            return
        }
        if let description = codexTrimmedString(value["description"]) {
            found = "Description: \(description)"
            return
        }
        if let valueText = codexTrimmedString(value["value"]) ?? codexTrimmedString(value["textContent"]) {
            found = valueText
            return
        }
        for child in codexSemanticChildren(of: value) {
            visit(child)
        }
    }

    for child in codexSemanticChildren(of: element) {
        visit(child)
        if found != nil {
            break
        }
    }
    return found
}

private func codexElementDigest(_ element: JSONObject) -> String {
    var parts = [
        codexRoleName(element),
        codexTrimmedString(element["title"]) ?? "",
        codexTrimmedString(element["description"]) ?? "",
        codexTrimmedString(element["value"]) ?? "",
        codexTrimmedString(element["textContent"]) ?? "",
        codexTrimmedString(element["identifier"]) ?? "",
        codexPrimaryDescendantLabel(element) ?? ""
    ]
    if let position = element["position"] as? JSONObject {
        parts.append("\(Int(numberValue(position["x"]) ?? 0))")
        parts.append("\(Int(numberValue(position["y"]) ?? 0))")
    }
    if let size = element["size"] as? JSONObject {
        parts.append("\(Int(numberValue(size["width"]) ?? 0))")
        parts.append("\(Int(numberValue(size["height"]) ?? 0))")
    }
    return parts.joined(separator: "|")
}

private func codexRoleName(_ element: JSONObject) -> String {
    if let role = codexTrimmedString(element["role"]) {
        switch role {
        case "AXRow", "AXOutlineRow":
            return "row"
        case "AXCell":
            return "cell"
        case "AXStaticText":
            return "text"
        default:
            break
        }
    }
    if let roleDescription = codexTrimmedString(element["roleDescription"]) {
        if ["outline row", "外框行"].contains(roleDescription) {
            return "row"
        }
        if ["cell", "单元格"].contains(roleDescription) {
            return "cell"
        }
        return roleDescription
    }
    guard let role = codexTrimmedString(element["role"]) else {
        return "element"
    }
    switch role {
    case "AXButton":
        return "button"
    case "AXCheckBox":
        return "checkbox"
    case "AXMenuButton", "AXPopUpButton":
        return "menu button"
    case "AXRadioButton":
        return "radio button"
    case "AXScrollArea":
        return "scroll area"
    case "AXScrollBar":
        return "scroll bar"
    case "AXSplitGroup":
        return "split group"
    case "AXSplitter":
        return "splitter"
    case "AXSwitch":
        return "switch"
    case "AXTextArea":
        return "text area"
    case "AXTextField":
        return "text field"
    case "AXToolbar":
        return "toolbar"
    case "AXValueIndicator":
        return "value indicator"
    case "AXWindow":
        return "standard window"
    default:
        break
    }
    if role.hasPrefix("AX") {
        return String(role.dropFirst(2)).lowercased()
    }
    return role
}

private func codexIsSelected(_ element: JSONObject) -> Bool {
    if element["selected"] as? Bool == true {
        return true
    }
    if codexTrimmedString(element["selectedText"]) != nil {
        return true
    }
    if let selectedRows = element["selectedRows"] as? [Any], !selectedRows.isEmpty {
        return true
    }
    if let selectedChildren = element["selectedChildren"] as? [Any], !selectedChildren.isEmpty {
        return true
    }
    return false
}

private func codexTrimmedString(_ value: Any?) -> String? {
    guard let string = value as? String else {
        return nil
    }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func codexEscapeAttribute(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
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
