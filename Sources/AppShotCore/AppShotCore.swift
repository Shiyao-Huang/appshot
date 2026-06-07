import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import Vision

public typealias JSONObject = [String: Any]

public let browserAnnotationScreenshotsModeSettingKey = "browser-annotation-screenshots-mode"
public let browserAnnotationScreenshotsModeAlways = "always"
public let browserAnnotationScreenshotsModeNecessary = "necessary"
public let browserAnnotationScreenshotsModeValues = [
    browserAnnotationScreenshotsModeAlways,
    browserAnnotationScreenshotsModeNecessary
]
public let browserInteractionModeDefault = "comment"
public let browserAnnotationEditorModeComment = "comment"
public let browserAnnotationEditorModeDesign = "design"
public let browserAnnotationEditorModeValues = [
    browserAnnotationEditorModeComment,
    browserAnnotationEditorModeDesign
]
public let codexBrowserRuntimeEventTypes = [
    "browser-sidebar-runtime-clear-comment-screenshot",
    "browser-sidebar-runtime-close-comment-preview",
    "browser-sidebar-runtime-close-editor",
    "browser-sidebar-runtime-comment-screenshot-ready",
    "browser-sidebar-runtime-create-comment-at-point",
    "browser-sidebar-runtime-design-modifier-state",
    "browser-sidebar-runtime-design-scrub-changed",
    "browser-sidebar-runtime-exit-comment-mode",
    "browser-sidebar-runtime-focus-editor",
    "browser-sidebar-runtime-image-drag-ended",
    "browser-sidebar-runtime-image-drag-started",
    "browser-sidebar-runtime-message",
    "browser-sidebar-runtime-mouse-navigation",
    "browser-sidebar-runtime-open-comment-preview",
    "browser-sidebar-runtime-open-design-editor",
    "browser-sidebar-runtime-open-design-editor-at-point",
    "browser-sidebar-runtime-open-editor",
    "browser-sidebar-runtime-prepare-comment-screenshot",
    "browser-sidebar-runtime-restore-editor",
    "browser-sidebar-runtime-select-comment",
    "browser-sidebar-runtime-sync",
    "browser-sidebar-runtime-update-anchor"
]
public let appShotCaptureRequestNotificationName = "com.qppshot.AppShot.CaptureRequest"

public func appShotCaptureRequestCacheTrigger(_ requestID: String) -> String {
    "app-request:\(requestID)"
}

public struct AppShotCaptureOptions {
    public var screenshotPath: String?
    public var includeScreenshot: Bool
    public var browserAnnotationScreenshotsMode: String
    public var browserInteractionMode: String
    public var browserAnnotationEditorMode: String
    public var browserIsAgentControllingBrowser: Bool
    public var browserCanUseTweaks: Bool
    public var browserIsDesignModifierPressed: Bool
    public var browserIsOriginalViewEnabled: Bool
    public var browserIsTweaksEditorOpen: Bool
    public var browserViewportScale: Double
    public var browserZoomPercent: Double?
    public var browserActiveDesignChange: JSONObject?
    public var includeBrowserDOM: Bool
    public var browserDOMTimeoutSeconds: TimeInterval
    public var browserDOMFixture: JSONObject?
    public var browserDOMInstallBridge: Bool
    public var browserDOMClearBridgeLog: Bool
    public var includeElectronDebugging: Bool
    public var electronDebuggingTimeoutSeconds: TimeInterval
    public var maxDepth: Int
    public var maxChildren: Int
    public var includeOCR: Bool
    public var maxOCRObservations: Int
    public var accessibilityTimeoutSeconds: TimeInterval
    public var screenshotTimeoutSeconds: TimeInterval
    public var activateTarget: Bool
    public var requestAppCapture: Bool
    public var appCaptureTimeoutSeconds: TimeInterval
    public var preferRecentCache: Bool
    public var writeCache: Bool
    public var cacheMaxAgeSeconds: TimeInterval
    public var cacheTrigger: String?
    public var targetWindowID: UInt32?
    public var targetProcessIdentifier: pid_t?
    public var targetBundleIdentifier: String?

    public init(
        screenshotPath: String? = nil,
        includeScreenshot: Bool = false,
        browserAnnotationScreenshotsMode: String = browserAnnotationScreenshotsModeNecessary,
        browserInteractionMode: String = browserInteractionModeDefault,
        browserAnnotationEditorMode: String = browserAnnotationEditorModeComment,
        browserIsAgentControllingBrowser: Bool = false,
        browserCanUseTweaks: Bool = true,
        browserIsDesignModifierPressed: Bool = false,
        browserIsOriginalViewEnabled: Bool = false,
        browserIsTweaksEditorOpen: Bool = false,
        browserViewportScale: Double = 1.0,
        browserZoomPercent: Double? = nil,
        browserActiveDesignChange: JSONObject? = nil,
        includeBrowserDOM: Bool = false,
        browserDOMTimeoutSeconds: TimeInterval = 1.5,
        browserDOMFixture: JSONObject? = nil,
        browserDOMInstallBridge: Bool = false,
        browserDOMClearBridgeLog: Bool = false,
        includeElectronDebugging: Bool = false,
        electronDebuggingTimeoutSeconds: TimeInterval = 2.0,
        maxDepth: Int = 60,
        maxChildren: Int = 240,
        includeOCR: Bool = false,
        maxOCRObservations: Int = 240,
        accessibilityTimeoutSeconds: TimeInterval = 20.0,
        screenshotTimeoutSeconds: TimeInterval = 3.0,
        activateTarget: Bool = true,
        requestAppCapture: Bool = false,
        appCaptureTimeoutSeconds: TimeInterval = 2.0,
        preferRecentCache: Bool = true,
        writeCache: Bool = false,
        cacheMaxAgeSeconds: TimeInterval = 15.0,
        cacheTrigger: String? = nil,
        targetWindowID: UInt32? = nil,
        targetProcessIdentifier: pid_t? = nil,
        targetBundleIdentifier: String? = nil
    ) {
        self.screenshotPath = screenshotPath
        self.includeScreenshot = includeScreenshot
        self.browserAnnotationScreenshotsMode = normalizedBrowserAnnotationScreenshotsMode(browserAnnotationScreenshotsMode)
        self.browserInteractionMode = normalizedBrowserInteractionMode(browserInteractionMode)
        self.browserAnnotationEditorMode = normalizedBrowserAnnotationEditorMode(browserAnnotationEditorMode)
        self.browserIsAgentControllingBrowser = browserIsAgentControllingBrowser
        self.browserCanUseTweaks = browserCanUseTweaks
        self.browserIsDesignModifierPressed = browserIsDesignModifierPressed
        self.browserIsOriginalViewEnabled = browserIsOriginalViewEnabled
        self.browserIsTweaksEditorOpen = browserIsTweaksEditorOpen
        self.browserViewportScale = browserViewportScale
        self.browserZoomPercent = browserZoomPercent
        self.browserActiveDesignChange = browserActiveDesignChange
        self.includeBrowserDOM = includeBrowserDOM
        self.browserDOMTimeoutSeconds = browserDOMTimeoutSeconds
        self.browserDOMFixture = browserDOMFixture
        self.browserDOMInstallBridge = browserDOMInstallBridge
        self.browserDOMClearBridgeLog = browserDOMClearBridgeLog
        self.includeElectronDebugging = includeElectronDebugging
        self.electronDebuggingTimeoutSeconds = electronDebuggingTimeoutSeconds
        self.maxDepth = maxDepth
        self.maxChildren = maxChildren
        self.includeOCR = includeOCR
        self.maxOCRObservations = maxOCRObservations
        self.accessibilityTimeoutSeconds = accessibilityTimeoutSeconds
        self.screenshotTimeoutSeconds = screenshotTimeoutSeconds
        self.activateTarget = activateTarget
        self.requestAppCapture = requestAppCapture
        self.appCaptureTimeoutSeconds = appCaptureTimeoutSeconds
        self.preferRecentCache = preferRecentCache
        self.writeCache = writeCache
        self.cacheMaxAgeSeconds = cacheMaxAgeSeconds
        self.cacheTrigger = cacheTrigger
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
        if shouldReadRecentCaptureCache(options),
           let cachedPayload = recentCaptureCache(options: options) {
            return cachedPayload
        }

        let appCaptureRequest = options.requestAppCapture && !options.writeCache
            ? requestGUIAppCapture(options: options)
            : nil
        if let payload = appCaptureRequest?.payload {
            return payload
        }

        if let processIdentifier = options.targetProcessIdentifier,
           options.targetWindowID == nil,
           options.targetBundleIdentifier == nil,
           !NSWorkspace.shared.runningApplications.contains(where: { $0.processIdentifier == processIdentifier }) {
            return try captureAuxiliaryProcess(
                pid: processIdentifier,
                options: options,
                appCaptureRequest: appCaptureRequest
            )
        }

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
        let targetActivation = options.activateTarget
            ? activateCaptureTarget(application: app, window: primaryWindow)
            : [
                "requested": false,
                "reason": "disabled"
            ] as JSONObject
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let browserAnnotationScreenshotsMode = normalizedBrowserAnnotationScreenshotsMode(options.browserAnnotationScreenshotsMode)
        let includeBrowserAnnotationScreenshot = browserAnnotationScreenshotsMode == browserAnnotationScreenshotsModeAlways
        let screenshot = try maybeCaptureScreenshot(
            include: options.includeScreenshot || includeBrowserAnnotationScreenshot || options.screenshotPath != nil || options.includeOCR,
            requestedPath: options.screenshotPath,
            windowID: windowID,
            timeoutSeconds: options.screenshotTimeoutSeconds
        )

        let permissionPayload = permissions(prompt: false)
        var payload: JSONObject = [
            "schemaVersion": 1,
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "permissions": permissionPayload,
            "codexAppsStatus": codexAppsStatus(permissions: permissionPayload),
            "frontmostApplication": appInfo(frontmostApp ?? app),
            "currentApplication": appInfo(app),
            "targetApplication": appInfo(app),
            "targetActivation": targetActivation,
            "codexBrowserSettings": codexBrowserSettingsPayload(annotationScreenshotsMode: browserAnnotationScreenshotsMode),
            "windows": windows,
            "accessibility": accessibilitySnapshot(
                pid: pid,
                targetWindow: primaryWindow,
                maxDepth: options.maxDepth,
                maxChildren: options.maxChildren,
                timeoutSeconds: options.accessibilityTimeoutSeconds
            )
        ]
        if let appCaptureRequest {
            payload["appCaptureRequest"] = appCaptureRequest.diagnostics
        }

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
        payload["codexBrowserRuntimeState"] = codexBrowserRuntimeStatePayload(options: options)
        payload["codexBrowserRuntimeProtocol"] = codexBrowserRuntimeProtocolPayload(options: options)
        let shouldProbeElectronDebugging = options.includeElectronDebugging
            || (options.includeBrowserDOM && options.browserDOMFixture == nil && isLikelyElectronApplication(app))
        if shouldProbeElectronDebugging {
            payload["codexElectronRemoteDebugging"] = codexElectronRemoteDebuggingPayload(
                application: app,
                window: primaryWindow,
                options: options
            )
        }
        if options.includeBrowserDOM || options.browserDOMFixture != nil || options.browserDOMInstallBridge || options.browserDOMClearBridgeLog {
            var domIntegration = codexBrowserDOMIntegrationPayload(
                application: app,
                options: options
            )
            if domIntegration["available"] as? Bool != true,
               let electronDebugging = payload["codexElectronRemoteDebugging"] as? JSONObject,
               let domSnapshot = electronDebugging["domSnapshot"] as? JSONObject {
                domIntegration = codexBrowserDOMIntegrationPayload(
                    fromDOMSnapshot: domSnapshot,
                    appName: app.localizedName ?? app.bundleIdentifier ?? "Electron",
                    bundleIdentifier: app.bundleIdentifier ?? "",
                    options: options,
                    source: "electron-cdp-probe"
                )
                domIntegration["electronRemoteDebugging"] = codexElectronRemoteDebuggingSummary(electronDebugging)
            } else if let electronDebugging = payload["codexElectronRemoteDebugging"] as? JSONObject {
                domIntegration["electronRemoteDebugging"] = codexElectronRemoteDebuggingSummary(electronDebugging)
            }
            payload["codexBrowserDOMIntegration"] = domIntegration
        }
        payload["codexBrowserPayload"] = codexBrowserPayload(from: payload, annotationScreenshotsMode: browserAnnotationScreenshotsMode)
        if options.writeCache {
            payload = try payloadByWritingCaptureCache(
                payload,
                trigger: options.cacheTrigger ?? "capture",
                maxAgeSeconds: options.cacheMaxAgeSeconds
            )
        } else {
            payload["captureCache"] = captureCacheMetadata(
                hit: false,
                trigger: nil,
                writtenAt: nil,
                ageSeconds: nil,
                maxAgeSeconds: options.cacheMaxAgeSeconds,
                reason: shouldReadRecentCaptureCache(options) ? "miss" : cacheBypassReason(options),
                servedAt: nil
            )
        }
        payload["codex"] = codexSummaryPayload(from: payload)
        return payload
    }

    private static func captureAuxiliaryProcess(
        pid: pid_t,
        options: AppShotCaptureOptions,
        appCaptureRequest: GUIAppCaptureRequestResult?
    ) throws -> JSONObject {
        let permissionPayload = permissions(prompt: false)
        let processPayload = processInfo(pid: pid)
        let browserAnnotationScreenshotsMode = normalizedBrowserAnnotationScreenshotsMode(options.browserAnnotationScreenshotsMode)
        var payload: JSONObject = [
            "schemaVersion": 1,
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "permissions": permissionPayload,
            "codexAppsStatus": codexAppsStatus(permissions: permissionPayload),
            "frontmostApplication": NSWorkspace.shared.frontmostApplication.map { appInfo($0) } ?? NSNull(),
            "currentApplication": processPayload,
            "targetApplication": processPayload,
            "targetSelection": [
                "type": "pid",
                "pid": pid
            ],
            "targetActivation": [
                "requested": false,
                "reason": "auxiliaryProcess"
            ],
            "auxiliaryProcessCapture": [
                "requested": true,
                "reason": "pidNotNSRunningApplication",
                "process": processPayload
            ],
            "codexBrowserSettings": codexBrowserSettingsPayload(annotationScreenshotsMode: browserAnnotationScreenshotsMode),
            "windows": [],
            "primaryWindow": NSNull(),
            "currentWindow": NSNull(),
            "frontmostWindow": NSNull(),
            "accessibility": accessibilitySnapshot(
                pid: pid,
                targetWindow: nil,
                maxDepth: options.maxDepth,
                maxChildren: options.maxChildren,
                timeoutSeconds: options.accessibilityTimeoutSeconds
            )
        ]
        if let appCaptureRequest {
            payload["appCaptureRequest"] = appCaptureRequest.diagnostics
        }
        if options.includeScreenshot || options.includeOCR || options.screenshotPath != nil {
            payload["screenshot"] = [
                "captured": false,
                "reason": "auxiliaryProcessHasNoWindow"
            ]
        }
        if options.includeOCR {
            payload["ocr"] = ocrSnapshot(
                screenshotPath: options.screenshotPath,
                screenshotCaptured: false,
                maxObservations: options.maxOCRObservations
            )
        }
        payload["codexBrowserRuntimeState"] = codexBrowserRuntimeStatePayload(options: options)
        payload["codexBrowserRuntimeProtocol"] = codexBrowserRuntimeProtocolPayload(options: options)
        payload["codexBrowserPayload"] = codexBrowserPayload(from: payload, annotationScreenshotsMode: browserAnnotationScreenshotsMode)
        if options.writeCache {
            payload = try payloadByWritingCaptureCache(
                payload,
                trigger: options.cacheTrigger ?? "capture",
                maxAgeSeconds: options.cacheMaxAgeSeconds
            )
        } else {
            payload["captureCache"] = captureCacheMetadata(
                hit: false,
                trigger: nil,
                writtenAt: nil,
                ageSeconds: nil,
                maxAgeSeconds: options.cacheMaxAgeSeconds,
                reason: shouldReadRecentCaptureCache(options) ? "miss" : cacheBypassReason(options),
                servedAt: nil
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

    public static func codexAppsStatus(prompt: Bool = false) -> JSONObject {
        codexAppsStatus(permissions: permissions(prompt: prompt))
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

        var blockers = appshotReadinessBlockers(
            hasAccessibility: hasAccessibility,
            hasScreenRecording: hasScreenRecording
        )
        let advisories = appshotReadinessAdvisories(permissions: permissionPayload)
        if frontmost == nil {
            blockers.append("No frontmost application is available.")
        }

        var payload: JSONObject = [
            "schemaVersion": 1,
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "state": blockers.isEmpty ? "ready" : "needsAttention",
            "permissions": permissionPayload,
            "codexAppsStatus": codexAppsStatus(permissions: permissionPayload),
            "windowCount": windows.count,
            "blockers": blockers,
            "advisories": advisories,
            "captureCache": captureCacheStatus(),
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

    private static let appshotMCPToolNames = [
        "appshot_capture",
        "appshot_permissions",
        "appshot_status",
        "appshot_list_windows",
        "appshot_codex_apps_status"
    ]

    private static func appshotReadinessBlockers(
        hasAccessibility: Bool,
        hasScreenRecording: Bool
    ) -> [String] {
        var blockers: [String] = []
        if !hasAccessibility {
            blockers.append("Accessibility permission is off; text/UI tree will be shallow.")
        }
        if !hasScreenRecording {
            blockers.append("Screen Recording permission is off; screenshots may fail.")
        }
        return blockers
    }

    private static func appshotReadinessAdvisories(permissions permissionPayload: JSONObject) -> [String] {
        guard let stability = permissionPayload["stability"] as? JSONObject,
              let warning = stability["warning"] as? String,
              !warning.isEmpty else {
            return []
        }
        return [warning]
    }

    private static func codexAppsStatus(permissions permissionPayload: JSONObject) -> JSONObject {
        let hasAccessibility = permissionPayload["accessibility"] as? Bool ?? false
        let hasScreenRecording = permissionPayload["screenRecording"] as? Bool ?? false
        let blockers = appshotReadinessBlockers(
            hasAccessibility: hasAccessibility,
            hasScreenRecording: hasScreenRecording
        )
        let advisories = appshotReadinessAdvisories(permissions: permissionPayload)
        let ready = blockers.isEmpty
        let toolNames = appshotMCPToolNames
        let identity = permissionPayload["identity"] as? JSONObject ?? [:]
        let stability = permissionPayload["stability"] as? JSONObject ?? [:]
        let connector: JSONObject = [
            "id": "appshot",
            "name": "AppShot",
            "kind": "mcp-accessible-app",
            "bundleIdentifier": identity["bundleIdentifier"] ?? "com.qppshot.AppShot",
            "bundlePath": identity["bundlePath"] ?? "",
            "executablePath": identity["executablePath"] ?? "",
            "stableGrantTarget": stability["recommendedGrantTarget"] ?? [:],
            "ready": ready,
            "codexAppsReady": ready,
            "state": ready ? "ready" : "needsAttention",
            "tools": toolNames.map { ["name": $0] as JSONObject },
            "toolCount": toolNames.count,
            "blockers": blockers,
            "advisories": advisories
        ]
        return [
            "schemaVersion": 1,
            "format": "codex-accessible-connectors-status",
            "source": "appshot-codex-apps-status",
            "codexAppsReady": ready,
            "forceRefetchSupported": true,
            "retryWhenNotReady": true,
            "connectors": [connector],
            "connectorCount": 1,
            "accessibleConnectors": ready ? [connector] : [],
            "accessibleConnectorCount": ready ? 1 : 0,
            "tools": toolNames,
            "toolCount": toolNames.count,
            "blockers": blockers,
            "advisories": advisories,
            "evidence": [
                "focusedDiff": "codex-522/artifacts/appshots-focused-diff-v0.132.0..v0.133.0.patch",
                "anchors": [
                    "AccessibleConnectorsStatus",
                    "codex_apps_ready",
                    "force_refetch",
                    "ConnectorsSnapshot"
                ]
            ]
        ]
    }

    public static func captureCacheStatus(maxAgeSeconds: TimeInterval = 15.0) -> JSONObject {
        let url = captureCacheURL()
        var payload: JSONObject = [
            "path": url.path,
            "available": false,
            "recent": false,
            "maxAgeSeconds": maxAgeSeconds
        ]

        guard let entry = readCaptureCache() else {
            return payload
        }

        let ageSeconds = entry.writtenAt.map { max(0, Date().timeIntervalSince($0)) }
        let metadata = entry.payload["captureCache"] as? JSONObject
        payload["available"] = true
        payload["recent"] = ageSeconds.map { $0 <= maxAgeSeconds } ?? false
        if let ageSeconds {
            payload["ageSeconds"] = roundedSeconds(ageSeconds)
        }
        if let writtenAt = metadata?["writtenAt"] {
            payload["writtenAt"] = writtenAt
        }
        if let trigger = metadata?["trigger"] {
            payload["trigger"] = trigger
        }
        if let app = entry.payload["targetApplication"] as? JSONObject
            ?? entry.payload["currentApplication"] as? JSONObject
            ?? entry.payload["frontmostApplication"] as? JSONObject {
            payload["targetApplication"] = app
        }
        if let window = entry.payload["primaryWindow"] as? JSONObject
            ?? entry.payload["currentWindow"] as? JSONObject
            ?? entry.payload["frontmostWindow"] as? JSONObject {
            payload["primaryWindow"] = window
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

    private static func shouldReadRecentCaptureCache(_ options: AppShotCaptureOptions) -> Bool {
        options.preferRecentCache
            && !options.writeCache
            && options.screenshotPath == nil
            && !options.includeBrowserDOM
            && options.browserDOMFixture == nil
            && !options.browserDOMInstallBridge
            && !options.browserDOMClearBridgeLog
            && options.targetWindowID == nil
            && options.targetProcessIdentifier == nil
            && options.targetBundleIdentifier == nil
    }

    private static func cacheBypassReason(_ options: AppShotCaptureOptions) -> String {
        if options.writeCache {
            return "writeRequested"
        }
        if !options.preferRecentCache {
            return "disabled"
        }
        if options.screenshotPath != nil {
            return "explicitScreenshotPath"
        }
        if options.includeBrowserDOM || options.browserDOMFixture != nil || options.browserDOMInstallBridge || options.browserDOMClearBridgeLog {
            return "browserDOMRequested"
        }
        if options.targetWindowID != nil {
            return "explicitWindowID"
        }
        if options.targetProcessIdentifier != nil {
            return "explicitProcessIdentifier"
        }
        if options.targetBundleIdentifier != nil {
            return "explicitBundleIdentifier"
        }
        return "unknown"
    }

    private static func recentCaptureCache(options: AppShotCaptureOptions) -> JSONObject? {
        guard let entry = readCaptureCache(),
              let writtenAt = entry.writtenAt else {
            return nil
        }

        let ageSeconds = Date().timeIntervalSince(writtenAt)
        guard ageSeconds >= 0, ageSeconds <= options.cacheMaxAgeSeconds else {
            return nil
        }
        guard captureCacheSatisfies(options: options, payload: entry.payload) else {
            return nil
        }

        var payload = entry.payload
        var metadata = (payload["captureCache"] as? JSONObject) ?? [:]
        metadata["hit"] = true
        metadata["path"] = entry.url.path
        metadata["ageSeconds"] = roundedSeconds(ageSeconds)
        metadata["maxAgeSeconds"] = options.cacheMaxAgeSeconds
        metadata["reason"] = "recent"
        metadata["servedAt"] = ISO8601DateFormatter().string(from: Date())
        if metadata["writtenAt"] == nil {
            metadata["writtenAt"] = ISO8601DateFormatter().string(from: writtenAt)
        }
        payload["captureCache"] = metadata
        let mode = codexBrowserAnnotationScreenshotsMode(from: payload)
        payload["codexBrowserSettings"] = codexBrowserSettingsPayload(annotationScreenshotsMode: mode)
        payload["codexBrowserRuntimeState"] = codexBrowserRuntimeStatePayload(options: options)
        payload["codexBrowserPayload"] = codexBrowserPayload(from: payload, annotationScreenshotsMode: mode)
        payload["codex"] = codexSummaryPayload(from: payload)
        return payload
    }

    private struct GUIAppCaptureRequestResult {
        var payload: JSONObject?
        var diagnostics: JSONObject
    }

    private static func requestGUIAppCapture(options: AppShotCaptureOptions) -> GUIAppCaptureRequestResult {
        let requestID = UUID().uuidString
        let trigger = appShotCaptureRequestCacheTrigger(requestID)
        var userInfo: [String: Any] = [
            "requestID": requestID,
            "includeScreenshot": options.includeScreenshot,
            "includeOCR": options.includeOCR,
            "browserAnnotationScreenshotsMode": normalizedBrowserAnnotationScreenshotsMode(options.browserAnnotationScreenshotsMode),
            "browserAnnotationEditorMode": normalizedBrowserAnnotationEditorMode(options.browserAnnotationEditorMode),
            "browserDesignModifierPressed": options.browserIsDesignModifierPressed,
            "browserOriginalViewEnabled": options.browserIsOriginalViewEnabled,
            "browserTweaksEditorOpen": options.browserIsTweaksEditorOpen,
            "includeBrowserDOM": options.includeBrowserDOM,
            "browserDOMInstallBridge": options.browserDOMInstallBridge,
            "maxDepth": options.maxDepth,
            "maxChildren": options.maxChildren,
            "accessibilityTimeoutSeconds": options.accessibilityTimeoutSeconds,
            "screenshotTimeoutSeconds": options.screenshotTimeoutSeconds
        ]
        if let targetWindowID = options.targetWindowID {
            userInfo["targetWindowID"] = Int(targetWindowID)
        }
        if let targetProcessIdentifier = options.targetProcessIdentifier {
            userInfo["targetProcessIdentifier"] = Int(targetProcessIdentifier)
        }
        if let targetBundleIdentifier = options.targetBundleIdentifier {
            userInfo["targetBundleIdentifier"] = targetBundleIdentifier
        }

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(appShotCaptureRequestNotificationName),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )

        let timeoutSeconds = max(0.1, options.appCaptureTimeoutSeconds)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let entry = readCaptureCache(),
               var payload = payloadFromGUIAppCaptureCacheEntry(
                   entry,
                   trigger: trigger,
                   options: options
               ) {
                var diagnostics: JSONObject = [
                    "requested": true,
                    "available": true,
                    "source": "AppShot.app",
                    "requestID": requestID,
                    "trigger": trigger,
                    "timeoutSeconds": timeoutSeconds,
                    "reason": "cacheWritten"
                ]
                diagnostics["cachePath"] = entry.url.path
                payload["appCaptureRequest"] = diagnostics
                return GUIAppCaptureRequestResult(payload: payload, diagnostics: diagnostics)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return GUIAppCaptureRequestResult(
            payload: nil,
            diagnostics: [
                "requested": true,
                "available": false,
                "source": "AppShot.app",
                "requestID": requestID,
                "trigger": trigger,
                "timeoutSeconds": timeoutSeconds,
                "reason": "timeoutWaitingForCache"
            ]
        )
    }

    private static func payloadFromGUIAppCaptureCacheEntry(
        _ entry: (payload: JSONObject, url: URL, writtenAt: Date?),
        trigger: String,
        options: AppShotCaptureOptions
    ) -> JSONObject? {
        guard let writtenAt = entry.writtenAt,
              let metadata = entry.payload["captureCache"] as? JSONObject,
              metadata["trigger"] as? String == trigger else {
            return nil
        }

        let ageSeconds = Date().timeIntervalSince(writtenAt)
        guard ageSeconds >= 0, ageSeconds <= max(options.cacheMaxAgeSeconds, options.appCaptureTimeoutSeconds + 2.0),
              captureCacheSatisfies(options: options, payload: entry.payload) else {
            return nil
        }

        var payload = entry.payload
        var updatedMetadata = metadata
        updatedMetadata["hit"] = true
        updatedMetadata["path"] = entry.url.path
        updatedMetadata["ageSeconds"] = roundedSeconds(ageSeconds)
        updatedMetadata["maxAgeSeconds"] = options.cacheMaxAgeSeconds
        updatedMetadata["reason"] = "appRequest"
        updatedMetadata["servedAt"] = ISO8601DateFormatter().string(from: Date())
        payload["captureCache"] = updatedMetadata
        let mode = codexBrowserAnnotationScreenshotsMode(from: payload)
        payload["codexBrowserSettings"] = codexBrowserSettingsPayload(annotationScreenshotsMode: mode)
        payload["codexBrowserRuntimeState"] = codexBrowserRuntimeStatePayload(options: options)
        payload["codexBrowserPayload"] = codexBrowserPayload(from: payload, annotationScreenshotsMode: mode)
        payload["codex"] = codexSummaryPayload(from: payload)
        return payload
    }

    private static func captureCacheSatisfies(options: AppShotCaptureOptions, payload: JSONObject) -> Bool {
        let requestedMode = normalizedBrowserAnnotationScreenshotsMode(options.browserAnnotationScreenshotsMode)
        let payloadMode = codexBrowserAnnotationScreenshotsMode(from: payload)
        guard payloadMode == requestedMode else {
            return false
        }

        if options.includeScreenshot || requestedMode == browserAnnotationScreenshotsModeAlways {
            guard let screenshot = payload["screenshot"] as? JSONObject,
                  screenshot["captured"] as? Bool == true,
                  let path = screenshot["path"] as? String,
                  FileManager.default.fileExists(atPath: path) else {
                return false
            }
        }

        if options.includeOCR {
            guard let ocr = payload["ocr"] as? JSONObject,
                  ocr["available"] as? Bool == true else {
                return false
            }
        }

        return true
    }

    private static func payloadByWritingCaptureCache(
        _ payload: JSONObject,
        trigger: String,
        maxAgeSeconds: TimeInterval
    ) throws -> JSONObject {
        let url = captureCacheURL()
        let writtenAt = ISO8601DateFormatter().string(from: Date())
        var cachedPayload = payload
        cachedPayload["captureCache"] = captureCacheMetadata(
            hit: false,
            trigger: trigger,
            writtenAt: writtenAt,
            ageSeconds: 0,
            maxAgeSeconds: maxAgeSeconds,
            reason: "written",
            servedAt: nil
        )
        let mode = codexBrowserAnnotationScreenshotsMode(from: cachedPayload)
        cachedPayload["codexBrowserSettings"] = codexBrowserSettingsPayload(annotationScreenshotsMode: mode)
        cachedPayload["codexBrowserPayload"] = codexBrowserPayload(from: cachedPayload, annotationScreenshotsMode: mode)
        cachedPayload["codex"] = codexSummaryPayload(from: cachedPayload)

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let data = try jsonString(cachedPayload, pretty: true).data(using: .utf8) else {
                throw AppShotError.jsonEncoding
            }
            try data.write(to: url, options: .atomic)
        } catch {
            throw AppShotError.writeFailed(url.path)
        }

        return cachedPayload
    }

    private static func captureCacheMetadata(
        hit: Bool,
        trigger: String?,
        writtenAt: String?,
        ageSeconds: TimeInterval?,
        maxAgeSeconds: TimeInterval,
        reason: String?,
        servedAt: String?
    ) -> JSONObject {
        var metadata: JSONObject = [
            "hit": hit,
            "path": captureCacheURL().path,
            "maxAgeSeconds": maxAgeSeconds
        ]
        if let trigger {
            metadata["trigger"] = trigger
        }
        if let writtenAt {
            metadata["writtenAt"] = writtenAt
        }
        if let ageSeconds {
            metadata["ageSeconds"] = roundedSeconds(ageSeconds)
        }
        if let reason {
            metadata["reason"] = reason
        }
        if let servedAt {
            metadata["servedAt"] = servedAt
        }
        return metadata
    }

    private static func readCaptureCache() -> (payload: JSONObject, url: URL, writtenAt: Date?)? {
        let url = captureCacheURL()
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? JSONObject else {
            return nil
        }

        let metadata = payload["captureCache"] as? JSONObject
        let writtenAtString = metadata?["writtenAt"] as? String
        let writtenAt = writtenAtString.flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)
        return (payload, url, writtenAt)
    }

    private static func captureCacheURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("AppShot", isDirectory: true)
            .appendingPathComponent("CapturePool", isDirectory: true)
            .appendingPathComponent("latest.json")
    }

    private static func roundedSeconds(_ value: TimeInterval) -> Double {
        (value * 1000).rounded() / 1000
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

private func activateCaptureTarget(application: NSRunningApplication, window: JSONObject?) -> JSONObject {
    let frontmostBefore = NSWorkspace.shared.frontmostApplication
    let targetPID = application.processIdentifier
    var payload: JSONObject = [
        "requested": true,
        "targetProcessIdentifier": targetPID,
        "frontmostBefore": frontmostBefore.map { appInfo($0) } ?? NSNull()
    ]

    let appActivateResult = application.activate(options: [.activateIgnoringOtherApps])
    payload["appActivateResult"] = appActivateResult

    let appElement = AXUIElementCreateApplication(targetPID)
    AXUIElementSetMessagingTimeout(appElement, 0.5)
    let axFrontmostResult = AXUIElementSetAttributeValue(
        appElement,
        kAXFrontmostAttribute as CFString,
        kCFBooleanTrue
    )
    payload["axFrontmostResult"] = String(describing: axFrontmostResult)

    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID {
            break
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    if let window {
        let match = matchingAXWindowResult(appElement: appElement, targetWindow: window)
        payload["axWindowMatchAfterActivation"] = match.diagnostics
        if let element = match.element {
            AXUIElementSetMessagingTimeout(element, 0.5)
            let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            let focusResult = AXUIElementSetAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            payload["axRaiseResult"] = String(describing: raiseResult)
            payload["axFocusedResult"] = String(describing: focusResult)
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        }
    }

    let frontmostAfter = NSWorkspace.shared.frontmostApplication
    payload["frontmostAfter"] = frontmostAfter.map { appInfo($0) } ?? NSNull()
    payload["frontmostMatchedTarget"] = frontmostAfter?.processIdentifier == targetPID
    return payload
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

private func processInfo(pid: pid_t) -> JSONObject {
    let executablePath = processExecutablePath(pid: pid) ?? ""
    let localizedName = executablePath.isEmpty
        ? "pid \(pid)"
        : URL(fileURLWithPath: executablePath).lastPathComponent
    return [
        "localizedName": localizedName,
        "bundleIdentifier": "",
        "bundleURL": "",
        "executableURL": executablePath,
        "processIdentifier": pid,
        "activationPolicy": NSApplication.ActivationPolicy.prohibited.rawValue
    ]
}

private func processExecutablePath(pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard result > 0 else {
        return nil
    }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

public func windowsForPID(_ pid: pid_t) -> [JSONObject] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [JSONObject] else {
        return []
    }

    return raw.enumerated().compactMap { index, info in
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
            "windowOrder": index,
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
    var electronAccessibility = enableElectronAccessibility(appElement)
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
    let targetWindowMatch = targetWindow.map {
        matchingAXWindowResult(appElement: appElement, targetWindow: $0)
    }
    let targetAXWindow = targetWindowMatch?.element
    let focusedAXWindow = focusedWindowResult == .success ? axElement(from: focusedWindow) : nil
    let mainAXWindow = mainWindowResult == .success ? axElement(from: mainWindow) : nil
    let windowFallback = [focusedAXWindow, mainAXWindow].compactMap { $0 }.first(where: axIsWindowElement)
    let rootElement = targetAXWindow ?? windowFallback ?? appElement
    var enhancedElements = [AXUIElement]()
    if let focusedAXElement = axElement(from: focusedElement) {
        enhancedElements.append(focusedAXElement)
    }
    enhancedElements.append(rootElement)
    enhancedElements.append(contentsOf: axEnhancementCandidateElements(rootElement))
    electronAccessibility["enhancedUserInterface"] = enableEnhancedUserInterface(enhancedElements)
    let rootSource: String
    if targetAXWindow != nil {
        rootSource = "targetWindow"
    } else if targetWindow != nil, windowFallback != nil {
        rootSource = "targetWindowUnmatchedFocusedWindow"
    } else if targetWindow != nil {
        rootSource = "targetWindowUnmatchedApplication"
    } else if windowFallback != nil {
        rootSource = "focusedWindow"
    } else {
        rootSource = "application"
    }
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
        "electronAccessibility": electronAccessibility,
        "rootSource": rootSource,
        "root": root
    ]

    if let targetWindow {
        payload["targetWindow"] = targetWindow
    }
    if let targetWindowMatch {
        payload["targetWindowMatch"] = targetWindowMatch.diagnostics
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

    let scopedDocumentPayload: JSONObject = [
        "root": root,
        "targetWindow": targetWindow as Any
    ]
    let scopedDocuments = documentReferences(from: scopedDocumentPayload)
    let documents = scopedDocuments.isEmpty ? documentReferences(from: root) : scopedDocuments
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
    out["elementID"] = elementID

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
        return [
            kAXChildrenAttribute,
            "AXVisibleChildren",
            "AXChildrenInNavigationOrder",
            "AXContents",
            "AXColumns",
            "AXVisibleColumns"
        ]
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
            "AXVisibleChildren",
            "AXChildrenInNavigationOrder"
        ]
    case "AXSplitGroup":
        return [
            kAXChildrenAttribute,
            "AXSplitters"
        ]
    case "AXWindow", "AXGroup", "AXToolbar":
        return [
            kAXChildrenAttribute,
            "AXVisibleChildren",
            "AXChildrenInNavigationOrder",
            "AXContents",
            "AXTabs",
            "AXSplitters"
        ]
    default:
        return dedupeStrings(discovered + axChildAttributes)
    }
}

public func enableElectronAccessibility(_ appElement: AXUIElement) -> JSONObject {
    AXUIElementSetMessagingTimeout(appElement, 0.5)
    let attributes = [
        "AXManualAccessibility",
        "AXEnhancedUserInterface"
    ]
    let attempts: [JSONObject] = attributes.map { attribute in
        let result = AXUIElementSetAttributeValue(
            appElement,
            attribute as CFString,
            kCFBooleanTrue
        )
        return [
            "attribute": attribute,
            "requested": true,
            "result": String(describing: result),
            "enabled": result == .success
        ]
    }
    let first = attempts.first ?? [
        "attribute": "AXManualAccessibility",
        "requested": true,
        "result": "notAttempted",
        "enabled": false
    ]
    return [
        "attribute": first["attribute"] ?? "AXManualAccessibility",
        "requested": true,
        "result": first["result"] ?? "notAttempted",
        "enabled": attempts.contains { $0["enabled"] as? Bool == true },
        "attempts": attempts
    ]
}

public func axEnhancementCandidateElements(
    _ rootElement: AXUIElement,
    maxDepth: Int = 3,
    maxElements: Int = 48
) -> [AXUIElement] {
    let childAttributes = [
        kAXChildrenAttribute as String,
        "AXVisibleChildren",
        "AXChildrenInNavigationOrder",
        "AXContents",
        "AXTabs",
        "AXRows",
        "AXVisibleRows"
    ]
    var out: [AXUIElement] = []
    var queue: [(AXUIElement, Int)] = [(rootElement, 0)]
    var seen = Set([axElementID(rootElement)])

    while !queue.isEmpty, out.count < maxElements {
        let (element, depth) = queue.removeFirst()
        guard depth < maxDepth else {
            continue
        }
        for attribute in childAttributes {
            for child in axChildElements(element, attribute: attribute) {
                let childID = axElementID(child)
                guard !seen.contains(childID) else {
                    continue
                }
                seen.insert(childID)
                out.append(child)
                if out.count >= maxElements {
                    break
                }
                queue.append((child, depth + 1))
            }
            if out.count >= maxElements {
                break
            }
        }
    }
    return out
}

public func enableEnhancedUserInterface(_ elements: [AXUIElement]) -> [JSONObject] {
    var seen = Set<String>()
    return elements.compactMap { element in
        let elementID = axElementID(element)
        guard !seen.contains(elementID) else {
            return nil
        }
        seen.insert(elementID)
        AXUIElementSetMessagingTimeout(element, 0.5)
        let result = AXUIElementSetAttributeValue(
            element,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
        return [
            "attribute": "AXEnhancedUserInterface",
            "elementID": elementID,
            "requested": true,
            "result": String(describing: result),
            "enabled": result == .success
        ]
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
        "AXGroup",
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
    case "AXTextArea", "AXTextField", "AXWebArea":
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
    matchingAXWindowResult(appElement: appElement, targetWindow: targetWindow).element
}

private struct AXWindowCandidate {
    let element: AXUIElement
    let sources: [String]
}

private func matchingAXWindowResult(
    appElement: AXUIElement,
    targetWindow: JSONObject
) -> (element: AXUIElement?, diagnostics: JSONObject) {
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
    var candidatePairs: [(source: String, element: AXUIElement)] = []
    if focusedWindowResult == .success, let focusedWindow {
        candidatePairs.append(("focusedWindow", focusedWindow as! AXUIElement))
    }
    if mainWindowResult == .success, let mainWindow {
        candidatePairs.append(("mainWindow", mainWindow as! AXUIElement))
    }
    for attribute in [
        kAXWindowsAttribute,
        "AXVisibleChildren",
        kAXChildrenAttribute,
        "AXChildrenInNavigationOrder",
        "AXContents"
    ] {
        for element in axChildElements(appElement, attribute: attribute) {
            candidatePairs.append((attribute, element))
        }
    }

    var candidatesByID: [String: AXWindowCandidate] = [:]
    var candidateOrder: [String] = []
    for pair in candidatePairs {
        let id = axElementID(pair.element)
        if let existing = candidatesByID[id] {
            candidatesByID[id] = AXWindowCandidate(
                element: existing.element,
                sources: dedupeStrings(existing.sources + [pair.source])
            )
        } else {
            candidatesByID[id] = AXWindowCandidate(element: pair.element, sources: [pair.source])
            candidateOrder.append(id)
        }
    }
    let candidates = candidateOrder.compactMap { candidatesByID[$0] }

    let targetTitle = (targetWindow["title"] as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let targetBounds = targetWindow["bounds"] as? JSONObject
    let targetWindowNumber = numberValue(targetWindow["windowNumber"]) ?? numberValue(targetWindow["windowID"])
    var best: (score: Double, element: AXUIElement, diagnostics: JSONObject)?
    var scoredCandidates: [JSONObject] = []
    var roleCounts: [String: Int] = [:]

    for candidate in candidates {
        let window = candidate.element
        var score = 0.0
        var reasons: [String] = []
        let role = copyAXValue(window, kAXRoleAttribute) as? String ?? ""
        roleCounts[role.isEmpty ? "unknown" : role, default: 0] += 1
        if role == "AXWindow" {
            score += 20
            reasons.append("role")
        }
        let axTitle = (copyAXValue(window, kAXTitleAttribute) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !targetTitle.isEmpty && !axTitle.isEmpty {
            if axTitle == targetTitle {
                score += 120
                reasons.append("titleExact")
            } else if axTitle.contains(targetTitle) || targetTitle.contains(axTitle) {
                score += 50
                reasons.append("titleContains")
            }
        }

        let axWindowNumber = numberValue(copyAXValue(window, "AXWindowNumber"))
        if let targetWindowNumber,
           let axWindowNumber,
           abs(targetWindowNumber - axWindowNumber) < 0.5 {
            score += 200
            reasons.append("windowNumber")
        }

        var candidatePayload: JSONObject = [
            "score": score,
            "role": role,
            "title": axTitle,
            "sources": candidate.sources,
            "reasons": reasons
        ]
        if let axWindowNumber {
            candidatePayload["windowNumber"] = axWindowNumber
        }

        if let position = copyAXValue(window, kAXPositionAttribute),
           let point = axPoint(position) {
            candidatePayload["position"] = ["x": point.x, "y": point.y]
        }
        if let size = copyAXValue(window, kAXSizeAttribute),
           let cgSize = axSize(size) {
            candidatePayload["size"] = ["width": cgSize.width, "height": cgSize.height]
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
            candidatePayload["boundsDelta"] = delta
            if delta < 12 {
                score += 120
                reasons.append("boundsExact")
            } else if delta < 80 {
                score += 60
                reasons.append("boundsNear")
            }
        }
        candidatePayload["score"] = score
        candidatePayload["reasons"] = reasons

        scoredCandidates.append(candidatePayload)

        if score > (best?.score ?? 0) {
            best = (score, window, candidatePayload)
        }
    }

    scoredCandidates.sort {
        (($0["score"] as? Double) ?? 0) > (($1["score"] as? Double) ?? 0)
    }
    let matched = (best?.score ?? 0) > 0
    let hasAXWindowRoles = (roleCounts["AXWindow"] ?? 0) > 0
    let suspectedSelfReferentialAXWindows = !hasAXWindowRoles
        && candidates.count > 0
        && ((roleCounts["AXApplication"] ?? 0) > 0 || (roleCounts["unknown"] ?? 0) > 0)
    var diagnostics: JSONObject = [
        "matched": matched,
        "candidateCount": candidates.count,
        "axWindowExposure": [
            "hasAXWindowRoles": hasAXWindowRoles,
            "roleCounts": roleCounts,
            "suspectedSelfReferentialAXWindows": suspectedSelfReferentialAXWindows
        ],
        "bestScore": best?.score ?? 0,
        "bestCandidate": best?.diagnostics ?? [:],
        "topCandidates": Array(scoredCandidates.prefix(8)),
        "targetTitle": targetTitle,
        "focusedWindowResult": String(describing: focusedWindowResult),
        "mainWindowResult": String(describing: mainWindowResult),
        "recoverySteps": matched ? [] : [
            "Activate the target app/window and retry capture so macOS Accessibility exposes AXWindow candidates.",
            "For Electron apps such as VS Code, enable screen reader accessibility support in the target app when available.",
            "Use --include-screenshot or --include-ocr only as fallback evidence when AXWindow matching is unavailable."
        ]
    ]
    if let targetWindowNumber {
        diagnostics["targetWindowNumber"] = targetWindowNumber
    }
    if let targetBounds {
        diagnostics["targetBounds"] = targetBounds
    }
    return (matched ? best?.element : nil, diagnostics)
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
          let parameter = axRangeValue(range) else {
        return nil
    }

    var candidates: [String] = []
    for attribute in ["AXStringForRange", "AXAttributedStringForRange"] {
        guard let value = copyAXParameterizedValue(element, attribute, parameter: parameter),
              let text = axText(fromParameterizedValue: value) else {
            continue
        }
        candidates.append(text)
    }

    guard let text = candidates
        .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        .filter({ !$0.isEmpty })
        .max(by: { $0.count < $1.count }) else {
        return nil
    }

    return AXParameterizedText(text: text, range: range)
}

public func axText(fromParameterizedValue value: Any) -> String? {
    if let string = value as? String {
        return string
    }
    if let attributed = value as? NSAttributedString {
        return attributed.string
    }
    return nil
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

public func normalizedBrowserAnnotationScreenshotsMode(_ mode: String?) -> String {
    let candidate = mode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return browserAnnotationScreenshotsModeValues.contains(candidate)
        ? candidate
        : browserAnnotationScreenshotsModeNecessary
}

public func isValidBrowserAnnotationScreenshotsMode(_ mode: String) -> Bool {
    browserAnnotationScreenshotsModeValues.contains(mode)
}

public func normalizedBrowserInteractionMode(_ mode: String?) -> String {
    let candidate = mode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return candidate.isEmpty ? browserInteractionModeDefault : candidate
}

public func normalizedBrowserAnnotationEditorMode(_ mode: String?) -> String {
    let candidate = mode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return browserAnnotationEditorModeValues.contains(candidate)
        ? candidate
        : browserAnnotationEditorModeComment
}

public func isValidBrowserAnnotationEditorMode(_ mode: String) -> Bool {
    browserAnnotationEditorModeValues.contains(mode)
}

public func codexBrowserSettingsPayload(annotationScreenshotsMode: String) -> JSONObject {
    [
        browserAnnotationScreenshotsModeSettingKey: normalizedBrowserAnnotationScreenshotsMode(annotationScreenshotsMode),
        "annotationScreenshotsMode": normalizedBrowserAnnotationScreenshotsMode(annotationScreenshotsMode),
        "description": "When browser annotation screenshots are included",
        "schema": browserAnnotationScreenshotsModeValues
    ]
}

public func codexBrowserAnnotationScreenshotsMode(from payload: JSONObject) -> String {
    if let settings = payload["codexBrowserSettings"] as? JSONObject {
        if let mode = codexTrimmedString(settings[browserAnnotationScreenshotsModeSettingKey]) {
            return normalizedBrowserAnnotationScreenshotsMode(mode)
        }
        if let mode = codexTrimmedString(settings["annotationScreenshotsMode"]) {
            return normalizedBrowserAnnotationScreenshotsMode(mode)
        }
    }
    if let browserPayload = payload["codexBrowserPayload"] as? JSONObject,
       let metadata = browserPayload["localBrowserCommentMetadata"] as? JSONObject,
       let mode = codexTrimmedString(metadata["annotationScreenshotsMode"]) {
        return normalizedBrowserAnnotationScreenshotsMode(mode)
    }
    return browserAnnotationScreenshotsModeNecessary
}

public func codexBrowserRuntimeStatePayload(options: AppShotCaptureOptions) -> JSONObject {
    var out: JSONObject = [
        "format": "codex-browser-runtime-state-adapter",
        "source": "appshot-native-adapter",
        "type": "browser-sidebar-runtime-sync",
        "interactionMode": normalizedBrowserInteractionMode(options.browserInteractionMode),
        "annotationEditorMode": normalizedBrowserAnnotationEditorMode(options.browserAnnotationEditorMode),
        "isAgentControllingBrowser": options.browserIsAgentControllingBrowser,
        "canUseTweaks": options.browserCanUseTweaks,
        "isDesignModifierPressed": options.browserIsDesignModifierPressed,
        "isOriginalViewEnabled": options.browserIsOriginalViewEnabled,
        "isTweaksEditorOpen": options.browserIsTweaksEditorOpen,
        "comments": [],
        "intlConfig": NSNull(),
        "activeDesignChange": options.browserActiveDesignChange.map { $0 as Any } ?? NSNull(),
        "viewportScale": options.browserViewportScale,
        "zoomPercent": options.browserZoomPercent.map { $0 as Any } ?? NSNull(),
        "evidenceEvents": codexBrowserRuntimeEventTypes,
        "adapterOnly": true,
        "warning": "Adapter state only; AppShot does not run Codex browser DOM/preload design editor or tweaks IPC."
    ]

    if let activeDesignChange = options.browserActiveDesignChange {
        out["localBrowserDesignChange"] = activeDesignChange
    } else {
        out["localBrowserDesignChange"] = NSNull()
    }
    return out
}

public func codexBrowserRuntimeProtocolPayload(
    options: AppShotCaptureOptions,
    liveEventStreamAvailable: Bool = false
) -> JSONObject {
    [
        "format": "codex-browser-runtime-protocol-adapter",
        "source": "codex-macapp-522-evidence",
        "adapterSource": "appshot-native-adapter",
        "channel": "codex_desktop:browser-sidebar-runtime-message",
        "hostMessageAPI": [
            "send": "sendMessageToHost",
            "subscribe": "subscribeToHostMessages"
        ],
        "syncEventType": "browser-sidebar-runtime-sync",
        "eventTypes": codexBrowserRuntimeEventTypes,
        "eventTypeCount": codexBrowserRuntimeEventTypes.count,
        "settingsKeys": [
            browserAnnotationScreenshotsModeSettingKey
        ],
        "payloadKeys": [
            "localBrowserContext",
            "localBrowserCommentMetadata",
            "localBrowserAttachedImages",
            "localBrowserDesignChange",
            "localBrowserRuntimeProtocol",
            "localBrowserRuntimeEvents",
            "localBrowserScreenshot"
        ],
        "runtimeState": codexBrowserRuntimeStatePayload(options: options),
        "liveEventStreamAvailable": liveEventStreamAvailable,
        "adapterOnly": true,
        "evidence": [
            "../codex-522/mac-app/artifacts/comment-preload-runtime-events-522.txt",
            "../codex-522/mac-app/appshots-evidence/522-appshots-snippets.js",
            "../codex-522/mac-app/appshots-evidence/522-app-session-appshots-snippets.js"
        ],
        "warning": "Protocol evidence and AppShot candidate events only; a true Codex live browser preload stream requires an embedded browser/preload or extension helper."
    ]
}

public func codexBrowserDOMIntegrationPayload(
    application: NSRunningApplication,
    options: AppShotCaptureOptions
) -> JSONObject {
    let bundleIdentifier = application.bundleIdentifier ?? ""
    let appName = application.localizedName ?? bundleIdentifier

    if let fixture = options.browserDOMFixture {
        return codexBrowserDOMIntegrationPayload(
            fromDOMSnapshot: fixture,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            options: options,
            source: "fixture"
        )
    }

    guard options.includeBrowserDOM || options.browserDOMInstallBridge || options.browserDOMClearBridgeLog else {
        return [
            "format": "codex-browser-dom-integration",
            "source": "browser-apple-events-dom-probe",
            "available": false,
            "browserRuntimeEvents": [],
            "reason": "notRequested"
        ]
    }

    guard let script = browserDOMProbeScript(
        bundleIdentifier: bundleIdentifier,
        installBridge: options.browserDOMInstallBridge,
        clearBridgeLog: options.browserDOMClearBridgeLog
    ) else {
        return [
            "format": "codex-browser-dom-integration",
            "source": "browser-apple-events-dom-probe",
            "available": false,
            "supported": false,
            "browserBundleIdentifier": bundleIdentifier,
            "applicationName": appName,
            "browserRuntimeEvents": [],
            "reason": "unsupportedBrowser"
        ]
    }

    let result = runProcess(
        executablePath: "/usr/bin/osascript",
        arguments: ["-l", "JavaScript", "-e", script],
        timeoutSeconds: options.browserDOMTimeoutSeconds
    )

    guard !result.timedOut else {
        return [
            "format": "codex-browser-dom-integration",
            "source": "browser-apple-events-dom-probe",
            "available": false,
            "supported": true,
            "browserBundleIdentifier": bundleIdentifier,
            "applicationName": appName,
            "browserRuntimeEvents": [],
            "timedOut": true,
            "timeoutSeconds": options.browserDOMTimeoutSeconds,
            "reason": "timedOut"
        ]
    }

    guard result.exitStatus == 0 else {
        return [
            "format": "codex-browser-dom-integration",
            "source": "browser-apple-events-dom-probe",
            "available": false,
            "supported": true,
            "browserBundleIdentifier": bundleIdentifier,
            "applicationName": appName,
            "browserRuntimeEvents": [],
            "exitStatus": result.exitStatus,
            "stderr": result.stderr,
            "reason": "scriptFailed"
        ]
    }

    guard let domSnapshot = parseJSONObject(result.stdout) else {
        return [
            "format": "codex-browser-dom-integration",
            "source": "browser-apple-events-dom-probe",
            "available": false,
            "supported": true,
            "browserBundleIdentifier": bundleIdentifier,
            "applicationName": appName,
            "browserRuntimeEvents": [],
            "stdoutPreview": String(result.stdout.prefix(500)),
            "reason": "invalidJSON"
        ]
    }

    return codexBrowserDOMIntegrationPayload(
        fromDOMSnapshot: domSnapshot,
        appName: appName,
        bundleIdentifier: bundleIdentifier,
        options: options,
        source: "browser-apple-events-dom-probe"
    )
}

public func codexElectronRemoteDebuggingPayload(
    application: NSRunningApplication,
    window: JSONObject?,
    options: AppShotCaptureOptions
) -> JSONObject {
    let bundleIdentifier = application.bundleIdentifier ?? ""
    let appName = application.localizedName ?? bundleIdentifier
    let rootPID = application.processIdentifier
    let processIDs = electronProcessTreePIDs(rootPID: rootPID)
    let scannedPorts = electronCandidateDevToolsPorts(rootPID: rootPID, processIDs: processIDs)
    let deadline = Date().addingTimeInterval(max(0.2, options.electronDebuggingTimeoutSeconds))
    let probe = electronDevToolsTargets(scannedPorts: scannedPorts, deadline: deadline)
    let windowTitle = codexTrimmedString(window?["title"]) ?? ""
    let scoredTargets = probe.targets.map { target -> JSONObject in
        var out = target
        out["selectionScore"] = electronDevToolsTargetScore(target, windowTitle: windowTitle)
        return out
    }
    let selectedTarget = scoredTargets
        .filter { codexTrimmedString($0["webSocketDebuggerUrl"]) != nil }
        .sorted {
            let left = ($0["selectionScore"] as? Int) ?? 0
            let right = ($1["selectionScore"] as? Int) ?? 0
            if left == right {
                return (codexTrimmedString($0["title"]) ?? "") < (codexTrimmedString($1["title"]) ?? "")
            }
            return left > right
        }
        .first
    var cdpSnapshot: JSONObject = [
        "available": false,
        "reason": selectedTarget == nil ? "noWebSocketDebuggerTarget" : "notSampled"
    ]
    if let webSocketURL = codexTrimmedString(selectedTarget?["webSocketDebuggerUrl"]),
       Date() < deadline {
        cdpSnapshot = electronCDPSnapshot(
            webSocketDebuggerURL: webSocketURL,
            timeoutSeconds: max(0.2, deadline.timeIntervalSinceNow)
        )
    }

    var payload: JSONObject = [
        "format": "codex-electron-remote-debugging",
        "source": "electron-cdp-probe",
        "requested": true,
        "available": !probe.targets.isEmpty,
        "supported": isLikelyElectronApplication(application),
        "applicationName": appName,
        "bundleIdentifier": bundleIdentifier,
        "processIdentifier": rootPID,
        "processIDs": processIDs.map { Int($0) },
        "windowTitle": windowTitle,
        "knownPorts": Array(codexBrowserRemoteDebuggingPorts).sorted(),
        "scannedPorts": scannedPorts,
        "httpProbeCount": probe.probes.count,
        "httpProbes": probe.probes,
        "targetCount": scoredTargets.count,
        "targets": scoredTargets,
        "selectedTarget": selectedTarget.map { $0 as Any } ?? NSNull(),
        "cdpSnapshot": cdpSnapshot,
        "liveEventStreamAvailable": cdpSnapshot["available"] as? Bool ?? false,
        "adapterOnly": true,
        "evidence": [
            "../codex-522/mac-app/docs/appshots-macapp-architecture.md",
            "../codex-522/mac-app/appshots-evidence/522-appshots-snippets.js",
            "../codex-522/mac-app/artifacts/comment-preload-runtime-events-522.txt"
        ]
    ]

    if let domSnapshot = cdpSnapshot["domSnapshot"] as? JSONObject {
        payload["domSnapshot"] = domSnapshot
    }
    if probe.targets.isEmpty {
        payload["reason"] = "noInspectableTargets"
    } else if cdpSnapshot["available"] as? Bool == true {
        payload["reason"] = "cdpSnapshotAvailable"
    } else {
        payload["reason"] = codexTrimmedString(cdpSnapshot["reason"]) ?? "cdpSnapshotUnavailable"
    }
    return payload
}

public func codexElectronRemoteDebuggingSummary(_ payload: JSONObject) -> JSONObject {
    [
        "format": payload["format"] ?? "codex-electron-remote-debugging",
        "source": payload["source"] ?? "electron-cdp-probe",
        "available": payload["available"] ?? false,
        "supported": payload["supported"] ?? false,
        "reason": payload["reason"] ?? "",
        "scannedPorts": payload["scannedPorts"] ?? [],
        "targetCount": payload["targetCount"] ?? 0,
        "selectedTarget": payload["selectedTarget"] ?? NSNull(),
        "liveEventStreamAvailable": payload["liveEventStreamAvailable"] ?? false
    ]
}

private func isLikelyElectronApplication(_ application: NSRunningApplication) -> Bool {
    let bundleIdentifier = (application.bundleIdentifier ?? "").lowercased()
    if bundleIdentifier.contains("vscode") || bundleIdentifier.contains("electron") || bundleIdentifier.contains("codex") {
        return true
    }
    guard let bundleURL = application.bundleURL else {
        return false
    }
    let electronFramework = bundleURL
        .appendingPathComponent("Contents")
        .appendingPathComponent("Frameworks")
        .appendingPathComponent("Electron Framework.framework")
    return FileManager.default.fileExists(atPath: electronFramework.path)
}

private func electronProcessTreePIDs(rootPID: pid_t) -> [pid_t] {
    let result = runProcess(
        executablePath: "/bin/ps",
        arguments: ["-axo", "pid=,ppid="],
        timeoutSeconds: 0.8
    )
    guard result.exitStatus == 0 else {
        return [rootPID]
    }

    var childrenByParent = [pid_t: [pid_t]]()
    for line in result.stdout.split(separator: "\n") {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 2,
              let pidValue = Int32(parts[0]),
              let parentValue = Int32(parts[1]) else {
            continue
        }
        childrenByParent[pid_t(parentValue), default: []].append(pid_t(pidValue))
    }

    var out: [pid_t] = []
    var queue = [rootPID]
    var seen = Set<pid_t>()
    while let pid = queue.first, out.count < 160 {
        queue.removeFirst()
        guard !seen.contains(pid) else {
            continue
        }
        seen.insert(pid)
        out.append(pid)
        queue.append(contentsOf: childrenByParent[pid] ?? [])
    }
    return out
}

private func electronCandidateDevToolsPorts(rootPID: pid_t, processIDs: [pid_t]) -> [Int] {
    var ports = Set(codexBrowserRemoteDebuggingPorts)
    let pidList = Array(processIDs.prefix(80)).map { String(Int($0)) }.joined(separator: ",")
    if !pidList.isEmpty {
        let result = runProcess(
            executablePath: "/usr/sbin/lsof",
            arguments: ["-nP", "-a", "-p", pidList, "-iTCP", "-sTCP:LISTEN"],
            timeoutSeconds: 1.0
        )
        if result.exitStatus == 0 {
            for line in result.stdout.split(separator: "\n") {
                guard line.contains("(LISTEN)"),
                      let port = parseListeningPort(fromLsofLine: String(line)) else {
                    continue
                }
                ports.insert(port)
            }
        }
    }
    if ports.isEmpty {
        ports.formUnion(codexBrowserRemoteDebuggingPorts)
    }
    _ = rootPID
    return Array(ports).sorted().prefix(24).map { $0 }
}

private func parseListeningPort(fromLsofLine line: String) -> Int? {
    guard let tcpRange = line.range(of: "TCP ") else {
        return nil
    }
    let tail = line[tcpRange.upperBound...]
    guard let endpoint = tail.split(separator: " ").first,
          let colon = endpoint.lastIndex(of: ":") else {
        return nil
    }
    return Int(endpoint[endpoint.index(after: colon)...])
}

private func electronDevToolsTargets(scannedPorts: [Int], deadline: Date) -> (targets: [JSONObject], probes: [JSONObject]) {
    var targets: [JSONObject] = []
    var probes: [JSONObject] = []

    for port in scannedPorts {
        guard Date() < deadline else {
            probes.append([
                "port": port,
                "available": false,
                "reason": "deadlineExceeded"
            ])
            break
        }
        let timeout = max(0.12, min(0.35, deadline.timeIntervalSinceNow / 2.0))
        let versionValue = fetchLocalJSON(port: port, path: "/json/version", timeoutSeconds: timeout)
        let listValue = fetchLocalJSON(port: port, path: "/json/list", timeoutSeconds: timeout)
        let version = versionValue as? JSONObject
        let targetList: [JSONObject]
        if let array = listValue as? [JSONObject] {
            targetList = array
        } else if let object = listValue as? JSONObject {
            targetList = [object]
        } else {
            targetList = []
        }

        let available = version != nil || !targetList.isEmpty
        probes.append([
            "port": port,
            "available": available,
            "hasVersion": version != nil,
            "targetCount": targetList.count,
            "browser": codexTrimmedString(version?["Browser"]) ?? codexTrimmedString(version?["browser"]) ?? "",
            "protocolVersion": codexTrimmedString(version?["Protocol-Version"]) ?? codexTrimmedString(version?["protocolVersion"]) ?? ""
        ])
        for target in targetList {
            var out = target
            out["port"] = port
            if out["webSocketDebuggerUrl"] == nil,
               let webSocketPath = codexTrimmedString(target["webSocketDebuggerPath"]) {
                out["webSocketDebuggerUrl"] = "ws://127.0.0.1:\(port)\(webSocketPath)"
            }
            targets.append(out)
        }
    }

    return (targets, probes)
}

private func fetchLocalJSON(port: Int, path: String, timeoutSeconds: TimeInterval) -> Any? {
    let result = runProcess(
        executablePath: "/usr/bin/curl",
        arguments: [
            "-fsS",
            "--max-time",
            String(format: "%.2f", max(0.1, timeoutSeconds)),
            "http://127.0.0.1:\(port)\(path)"
        ],
        timeoutSeconds: max(0.2, timeoutSeconds + 0.15)
    )
    guard result.exitStatus == 0, !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    return parseJSONValue(result.stdout)
}

private func electronDevToolsTargetScore(_ target: JSONObject, windowTitle: String) -> Int {
    var score = 0
    let title = (codexTrimmedString(target["title"]) ?? "").lowercased()
    let url = (codexTrimmedString(target["url"]) ?? "").lowercased()
    let type = (codexTrimmedString(target["type"]) ?? "").lowercased()
    let normalizedWindowTitle = windowTitle.lowercased()

    if type == "page" || type == "webview" {
        score += 40
    }
    if codexTrimmedString(target["webSocketDebuggerUrl"]) != nil {
        score += 20
    }
    if !normalizedWindowTitle.isEmpty {
        if title == normalizedWindowTitle {
            score += 160
        } else if title.contains(normalizedWindowTitle) || normalizedWindowTitle.contains(title) {
            score += 80
        }
    }
    if url.hasPrefix("devtools://") {
        score -= 80
    }
    if url.contains("vscode") || url.contains("file://") || url.contains("localhost") {
        score += 10
    }
    return score
}

private func electronCDPSnapshot(webSocketDebuggerURL: String, timeoutSeconds: TimeInterval) -> JSONObject {
    let result = runProcess(
        executablePath: "/usr/bin/env",
        arguments: [
            "node",
            "-e",
            electronCDPProbeScript,
            webSocketDebuggerURL,
            String(Int(max(200, timeoutSeconds * 1000.0)))
        ],
        timeoutSeconds: max(0.4, timeoutSeconds + 0.25)
    )
    guard !result.timedOut else {
        return [
            "available": false,
            "reason": "timedOut",
            "timeoutSeconds": timeoutSeconds
        ]
    }
    guard result.exitStatus == 0 else {
        return [
            "available": false,
            "reason": "nodeProbeFailed",
            "exitStatus": result.exitStatus,
            "stderr": result.stderr
        ]
    }
    guard let payload = parseJSONObject(result.stdout) else {
        return [
            "available": false,
            "reason": "invalidJSON",
            "stdoutPreview": String(result.stdout.prefix(500)),
            "stderr": result.stderr
        ]
    }
    return payload
}

private let electronCDPProbeScript = #"""
const wsUrl = process.argv[1];
const timeoutMs = Number(process.argv[2] || 1500);
const done = (value) => {
  try { console.log(JSON.stringify(value)); } catch (error) { console.log(JSON.stringify({ available: false, reason: "jsonEncodeFailed", error: String(error) })); }
  process.exit(0);
};
if (typeof WebSocket !== "function") done({ available: false, reason: "nodeWebSocketUnavailable" });
let nextId = 1;
const pending = new Map();
const ws = new WebSocket(wsUrl);
const timer = setTimeout(() => done({ available: false, reason: "timedOut" }), timeoutMs);
function command(method, params = {}) {
  const id = nextId++;
  const payload = JSON.stringify({ id, method, params });
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    ws.send(payload);
  });
}
function rectOf(element) {
  if (!element || typeof element.getBoundingClientRect !== "function") return {};
  const rect = element.getBoundingClientRect();
  return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
}
function selectorFor(element) {
  if (!element || element.nodeType !== 1) return "";
  if (element.id) return "#" + CSS.escape(element.id);
  const attr = element.getAttribute("aria-label") || element.getAttribute("role") || element.getAttribute("data-testid");
  const name = element.localName || "element";
  if (attr) return name + "[" + JSON.stringify(attr) + "]";
  const parent = element.parentElement;
  if (!parent) return name;
  const siblings = Array.from(parent.children).filter((item) => item.localName === element.localName);
  const index = Math.max(0, siblings.indexOf(element)) + 1;
  return selectorFor(parent) + " > " + name + ":nth-of-type(" + index + ")";
}
function domSnapshot() {
  const bodyText = (document.body?.innerText || document.documentElement?.innerText || "").slice(0, 80000);
  const elementSelector = "button,a,input,textarea,select,[role],[aria-label],[contenteditable='true'],img,.monaco-editor,.terminal,.explorer-viewlet,.tabs-container,.panel";
  const designTargets = Array.from(document.querySelectorAll(elementSelector)).slice(0, 240).map((element, index) => ({
    index,
    selector: selectorFor(element),
    tagName: element.localName || "",
    role: element.getAttribute("role") || element.localName || "",
    label: element.getAttribute("aria-label") || element.getAttribute("title") || "",
    text: ((element.innerText || element.textContent || element.getAttribute("alt") || element.getAttribute("aria-label") || "") + "").trim().slice(0, 1000),
    rect: rectOf(element)
  })).filter((item) => item.text || item.label || item.role || item.rect.width || item.rect.height);
  const images = Array.from(document.images || []).slice(0, 120).map((image, index) => ({
    index,
    sourceUrl: image.currentSrc || image.src || "",
    alt: image.alt || "",
    selector: selectorFor(image),
    rect: rectOf(image),
    naturalSize: { width: image.naturalWidth || 0, height: image.naturalHeight || 0 }
  }));
  return {
    available: true,
    pageUrl: location.href,
    url: location.href,
    title: document.title,
    viewportSize: { width: innerWidth, height: innerHeight },
    devicePixelRatio,
    bodyText,
    textLineCount: bodyText.split(/\n+/).filter(Boolean).length,
    activeElement: document.activeElement ? {
      selector: selectorFor(document.activeElement),
      role: document.activeElement.getAttribute("role") || document.activeElement.localName || "",
      text: ((document.activeElement.innerText || document.activeElement.textContent || document.activeElement.getAttribute("aria-label") || "") + "").trim().slice(0, 1000),
      rect: rectOf(document.activeElement)
    } : null,
    designTargets,
    images
  };
}
function simplifyAXNode(node) {
  const prop = (value) => value && typeof value === "object" && "value" in value ? value.value : value;
  return {
    nodeId: node.nodeId,
    ignored: !!node.ignored,
    role: prop(node.role) || "",
    name: prop(node.name) || "",
    value: prop(node.value) || "",
    description: prop(node.description) || "",
    childIds: node.childIds || []
  };
}
ws.addEventListener("message", (event) => {
  let message;
  try { message = JSON.parse(event.data); } catch { return; }
  if (!message || message.id == null || !pending.has(message.id)) return;
  const entry = pending.get(message.id);
  pending.delete(message.id);
  if (message.error) entry.reject(message.error);
  else entry.resolve(message.result || {});
});
ws.addEventListener("error", (event) => done({ available: false, reason: "webSocketError", error: String(event.message || event.type || event) }));
ws.addEventListener("open", async () => {
  try {
    const runtime = await command("Runtime.evaluate", {
      expression: "(" + domSnapshot.toString() + ")()",
      returnByValue: true,
      awaitPromise: false
    });
    let ax = { nodes: [] };
    try { ax = await command("Accessibility.getFullAXTree", { depth: 8 }); } catch (error) { ax = { error: String(error?.message || error), nodes: [] }; }
    let documentRoot = null;
    try { documentRoot = await command("DOM.getDocument", { depth: 2, pierce: true }); } catch {}
    clearTimeout(timer);
    ws.close();
    const dom = runtime?.result?.value || {};
    done({
      available: true,
      source: "Chrome DevTools Protocol",
      domSnapshot: dom,
      accessibility: {
        available: Array.isArray(ax.nodes),
        nodeCount: Array.isArray(ax.nodes) ? ax.nodes.length : 0,
        nodes: Array.isArray(ax.nodes) ? ax.nodes.slice(0, 240).map(simplifyAXNode) : [],
        error: ax.error || null
      },
      documentRoot: documentRoot?.root ? {
        nodeId: documentRoot.root.nodeId,
        nodeName: documentRoot.root.nodeName,
        nodeType: documentRoot.root.nodeType,
        childNodeCount: documentRoot.root.childNodeCount || 0
      } : null
    });
  } catch (error) {
    clearTimeout(timer);
    done({ available: false, reason: "cdpCommandFailed", error: String(error?.message || error) });
  }
});
"""#

private struct ProcessRunResult {
    let exitStatus: Int32
    let timedOut: Bool
    let stdout: String
    let stderr: String
}

private func runProcess(
    executablePath: String,
    arguments: [String],
    timeoutSeconds: TimeInterval
) -> ProcessRunResult {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()
    } catch {
        return ProcessRunResult(
            exitStatus: -1,
            timedOut: false,
            stdout: "",
            stderr: String(describing: error)
        )
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }

    let timedOut = process.isRunning
    if timedOut {
        process.terminate()
    }
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    return ProcessRunResult(
        exitStatus: process.terminationStatus,
        timedOut: timedOut,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
}

private func codexBrowserDOMIntegrationPayload(
    fromDOMSnapshot domSnapshot: JSONObject,
    appName: String,
    bundleIdentifier: String,
    options: AppShotCaptureOptions,
    source: String
) -> JSONObject {
    let pageURL = codexTrimmedString(domSnapshot["pageUrl"])
        ?? codexTrimmedString(domSnapshot["url"])
        ?? ""
    let title = codexTrimmedString(domSnapshot["title"]) ?? ""
    let images = (domSnapshot["images"] as? [JSONObject]) ?? []
    let designTargets = (domSnapshot["designTargets"] as? [JSONObject]) ?? []
    let attachedImages = images.prefix(24).map { image -> JSONObject in
        [
            "sourceUrl": codexTrimmedString(image["sourceUrl"]) ?? codexTrimmedString(image["src"]) ?? "",
            "alt": codexTrimmedString(image["alt"]) ?? "",
            "selector": codexTrimmedString(image["selector"]) ?? "",
            "rect": image["rect"] as? JSONObject ?? [:],
            "naturalSize": image["naturalSize"] as? JSONObject ?? [:]
        ]
    }.filter { !(codexTrimmedString($0["sourceUrl"]) ?? "").isEmpty }

    let runtimeCandidateEvents = codexBrowserRuntimeEventCandidates(
        domSnapshot: domSnapshot,
        pageURL: pageURL,
        title: title,
        attachedImages: attachedImages,
        designTargets: designTargets,
        options: options
    )
    let runtimeBridge = domSnapshot["runtimeBridge"] as? JSONObject ?? [:]
    let runtimeBridgeEvents = ((runtimeBridge["events"] as? [JSONObject]) ?? (domSnapshot["browserRuntimeBridgeEvents"] as? [JSONObject]) ?? [])
        .prefix(200)
        .map { $0 }
    let liveEventStreamAvailable = (runtimeBridge["liveEventStreamAvailable"] as? Bool)
        ?? (runtimeBridge["installed"] as? Bool)
        ?? !runtimeBridgeEvents.isEmpty
    let runtimeEvents = runtimeBridgeEvents + runtimeCandidateEvents
    let runtimeEventTypes = Array(Set(runtimeEvents.compactMap { codexTrimmedString($0["type"]) })).sorted()
    let runtimeProtocol = codexBrowserRuntimeProtocolPayload(
        options: options,
        liveEventStreamAvailable: liveEventStreamAvailable
    )
    let remoteDebuggingTarget = codexBrowserRemoteDebuggingTarget(pageURL: pageURL, title: title)
    return [
        "format": "codex-browser-dom-integration",
        "source": source,
        "available": domSnapshot["available"] as? Bool ?? true,
        "supported": true,
        "browserBundleIdentifier": bundleIdentifier,
        "applicationName": appName,
        "pageUrl": pageURL,
        "title": title,
        "remoteDebuggingTarget": remoteDebuggingTarget,
        "viewportSize": domSnapshot["viewportSize"] as? JSONObject ?? [:],
        "devicePixelRatio": domSnapshot["devicePixelRatio"] ?? NSNull(),
        "images": attachedImages,
        "imageCount": attachedImages.count,
        "designTargets": Array(designTargets.prefix(24)),
        "designTargetCount": designTargets.count,
        "browserRuntimeBridge": runtimeBridge,
        "browserRuntimeBridgeEvents": Array(runtimeBridgeEvents),
        "browserRuntimeBridgeEventCount": runtimeBridgeEvents.count,
        "browserRuntimeCandidateEvents": runtimeCandidateEvents,
        "browserRuntimeCandidateEventCount": runtimeCandidateEvents.count,
        "browserRuntimeEvents": runtimeEvents,
        "browserRuntimeEventCount": runtimeEvents.count,
        "browserRuntimeEventTypes": runtimeEventTypes,
        "browserRuntimeProtocol": runtimeProtocol,
        "liveEventStreamAvailable": liveEventStreamAvailable,
        "localBrowserAttachedImages": attachedImages
    ]
}

private let codexBrowserRemoteDebuggingTitles: Set<String> = [
    "content shell remote debugging",
    "inspectable webcontents"
]

private let codexBrowserRemoteDebuggingPorts: Set<Int> = [9222, 9229]

private func codexBrowserRemoteDebuggingTarget(pageURL: String, title: String) -> JSONObject {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let titleMatched = codexBrowserRemoteDebuggingTitles.contains(normalizedTitle)

    var localDebugPortMatched = false
    var parsedHost = ""
    var parsedPort: Int?
    if let url = URL(string: pageURL) {
        parsedHost = (url.host ?? "").lowercased()
        parsedPort = url.port ?? (url.scheme == "http" ? 80 : url.scheme == "https" ? 443 : nil)
        if let port = parsedPort,
           codexBrowserIsLocalDebugHost(parsedHost),
           codexBrowserRemoteDebuggingPorts.contains(port) {
            localDebugPortMatched = true
        }
    }

    let isRemoteDebuggingTarget = titleMatched || localDebugPortMatched
    return [
        "isRemoteDebuggingTarget": isRemoteDebuggingTarget,
        "titleMatched": titleMatched,
        "localDebugPortMatched": localDebugPortMatched,
        "title": title,
        "host": parsedHost,
        "port": parsedPort.map { $0 as Any } ?? NSNull(),
        "knownTitles": Array(codexBrowserRemoteDebuggingTitles).sorted(),
        "knownPorts": Array(codexBrowserRemoteDebuggingPorts).sorted()
    ]
}

private func codexBrowserIsLocalDebugHost(_ host: String) -> Bool {
    if host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0" || host == "::1" || host == "[::1]" {
        return true
    }
    return host.hasSuffix(".localhost")
}

private func codexBrowserRuntimeEventCandidates(
    domSnapshot: JSONObject,
    pageURL: String,
    title: String,
    attachedImages: [JSONObject],
    designTargets: [JSONObject],
    options: AppShotCaptureOptions
) -> [JSONObject] {
    let viewportSize = domSnapshot["viewportSize"] as? JSONObject ?? [:]
    let firstTarget = designTargets.first ?? [
        "selector": "document",
        "role": "document",
        "text": title,
        "rect": ["x": 0, "y": 0, "width": viewportSize["width"] ?? 0, "height": viewportSize["height"] ?? 0]
    ]
    let anchorState = codexBrowserAnchorState(target: firstTarget, pageURL: pageURL, viewportSize: viewportSize)
    let designEditorState = codexBrowserDesignEditorState(target: firstTarget, index: 0)
    let point = codexBrowserViewportPoint(from: firstTarget["rect"] as? JSONObject ?? [:])
    let commentID = "appshot-comment-0"
    let runtimeState = codexBrowserRuntimeStatePayload(options: options)
    var events: [JSONObject] = []

    func append(_ type: String, _ fields: JSONObject = [:]) {
        var event: JSONObject = [
            "type": type,
            "candidate": true,
            "adapterOnly": true
        ]
        for (key, value) in fields {
            event[key] = value
        }
        events.append(event)
    }

    append("browser-sidebar-runtime-sync", [
        "state": runtimeState
    ])
    append("browser-sidebar-runtime-message", [
        "message": [
            "type": "browser-sidebar-runtime-sync",
            "state": runtimeState
        ]
    ])
    append("browser-sidebar-runtime-design-modifier-state", [
        "isDesignModifierPressed": options.browserIsDesignModifierPressed
    ])
    append("browser-sidebar-runtime-prepare-comment-screenshot", [
        "annotationScreenshotsMode": normalizedBrowserAnnotationScreenshotsMode(options.browserAnnotationScreenshotsMode),
        "anchorState": anchorState
    ])
    append("browser-sidebar-runtime-open-editor", [
        "anchorState": anchorState,
        "editorMode": normalizedBrowserAnnotationEditorMode(options.browserAnnotationEditorMode)
    ])
    append("browser-sidebar-runtime-create-comment-at-point", [
        "point": point,
        "anchorState": anchorState,
        "commentId": commentID
    ])
    append("browser-sidebar-runtime-update-anchor", [
        "anchorState": anchorState,
        "commentId": commentID
    ])
    append("browser-sidebar-runtime-focus-editor", [
        "commentId": commentID
    ])
    append("browser-sidebar-runtime-open-comment-preview", [
        "anchorState": anchorState,
        "commentId": commentID
    ])
    append("browser-sidebar-runtime-comment-screenshot-ready", [
        "commentId": commentID,
        "screenshot": NSNull()
    ])
    append("browser-sidebar-runtime-restore-editor", [
        "commentId": commentID
    ])
    append("browser-sidebar-runtime-select-comment", [
        "commentId": commentID
    ])
    append("browser-sidebar-runtime-close-comment-preview", [
        "commentId": commentID
    ])
    append("browser-sidebar-runtime-close-editor", [
        "commentId": commentID
    ])
    append("browser-sidebar-runtime-exit-comment-mode")
    append("browser-sidebar-runtime-mouse-navigation", [
        "point": point,
        "anchorState": anchorState
    ])
    append("browser-sidebar-runtime-open-design-editor", [
        "anchorState": anchorState,
        "designEditorState": designEditorState
    ])
    append("browser-sidebar-runtime-open-design-editor-at-point", [
        "point": point,
        "anchorState": anchorState,
        "designEditorState": designEditorState
    ])
    append("browser-sidebar-runtime-design-scrub-changed", [
        "anchorState": anchorState,
        "designEditorState": designEditorState,
        "designChange": options.browserActiveDesignChange.map { $0 as Any } ?? designEditorState
    ])

    for image in attachedImages.prefix(12) {
        let sourceURL = codexTrimmedString(image["sourceUrl"]) ?? ""
        append("browser-sidebar-runtime-image-drag-started", [
            "sourceUrl": sourceURL,
            "image": image
        ])
        append("browser-sidebar-runtime-image-drag-ended", [
            "sourceUrl": sourceURL,
            "image": image
        ])
    }

    append("browser-sidebar-runtime-clear-comment-screenshot", [
        "commentId": commentID
    ])

    return events
}

private func codexBrowserAnchorState(
    target: JSONObject,
    pageURL: String,
    viewportSize: JSONObject
) -> JSONObject {
    let selector = codexTrimmedString(target["selector"]) ?? ""
    let rect = target["rect"] as? JSONObject ?? [:]
    let role = codexTrimmedString(target["role"]) ?? codexTrimmedString(target["tagName"]) ?? "element"
    let text = codexTrimmedString(target["text"]) ?? codexTrimmedString(target["label"]) ?? ""
    return [
        "anchor": [
            "kind": "element",
            "selector": selector,
            "role": role,
            "text": text
        ],
        "framePath": [],
        "frameUrl": pageURL,
        "viewportSize": viewportSize,
        "cardViewportRect": rect,
        "markerViewportPoint": codexBrowserViewportPoint(from: rect)
    ]
}

private func codexBrowserDesignEditorState(target: JSONObject, index: Int) -> JSONObject {
    let selector = codexTrimmedString(target["selector"]) ?? ""
    let rect = target["rect"] as? JSONObject ?? [:]
    let role = codexTrimmedString(target["role"]) ?? codexTrimmedString(target["tagName"]) ?? "element"
    let text = codexTrimmedString(target["text"]) ?? codexTrimmedString(target["label"]) ?? ""
    return [
        "id": "appshot-design-\(index)",
        "selector": selector,
        "role": role,
        "text": text,
        "rect": rect,
        "declarations": []
    ]
}

private func codexBrowserViewportPoint(from rect: JSONObject) -> JSONObject {
    let x = codexNumber(rect["x"]) ?? 0
    let y = codexNumber(rect["y"]) ?? 0
    let width = codexNumber(rect["width"]) ?? 0
    let height = codexNumber(rect["height"]) ?? 0
    return [
        "x": x + (width / 2),
        "y": y + (height / 2)
    ]
}

private func browserDOMProbeScript(
    bundleIdentifier: String,
    installBridge: Bool,
    clearBridgeLog: Bool
) -> String? {
    let appName: String
    let chromeLike: Bool
    switch bundleIdentifier {
    case "com.apple.Safari":
        appName = "Safari"
        chromeLike = false
    case "com.google.Chrome":
        appName = "Google Chrome"
        chromeLike = true
    case "com.google.Chrome.canary":
        appName = "Google Chrome Canary"
        chromeLike = true
    case "com.microsoft.edgemac":
        appName = "Microsoft Edge"
        chromeLike = true
    case "com.brave.Browser":
        appName = "Brave Browser"
        chromeLike = true
    default:
        return nil
    }

    let pageProbe = browserDOMPageProbeJavaScript(
        installBridge: installBridge,
        clearBridgeLog: clearBridgeLog
    )
    return """
    const appName = \(javaScriptStringLiteral(appName));
    const domJS = \(javaScriptStringLiteral(pageProbe));
    const app = Application(appName);
    function fail(reason) {
      return JSON.stringify({ available: false, reason, pageUrl: "", title: "", images: [], designTargets: [] });
    }
    if (!app.running()) {
      fail("browserNotRunning");
    } else if (app.windows.length === 0) {
      fail("noBrowserWindows");
    } else {
      const tab = app.windows[0].\(chromeLike ? "activeTab" : "currentTab")();
      \(chromeLike ? "tab.execute({ javascript: domJS });" : "app.doJavaScript(domJS, { in: tab });")
    }
    """
}

private func browserDOMPageProbeJavaScript(
    installBridge: Bool,
    clearBridgeLog: Bool
) -> String {
    let installBridgeLiteral = installBridge ? "true" : "false"
    let clearBridgeLogLiteral = clearBridgeLog ? "true" : "false"
    return #"""
    JSON.stringify((function() {
      const appshotInstallBridge = \#(installBridgeLiteral);
      const appshotClearBridgeLog = \#(clearBridgeLogLiteral);
      const appshotBridgeVersion = "0.1.12";
      const appshotBridgeSource = "appshot-browser-runtime-bridge";
      function textOf(element) {
        return (element.innerText || element.alt || element.getAttribute("aria-label") || element.title || element.value || "").replace(/\s+/g, " ").trim().slice(0, 240);
      }
      function elementFromEventTarget(target) {
        if (!target) return document.documentElement;
        if (target.nodeType === 1) return target;
        if (target.parentElement) return target.parentElement;
        return document.documentElement;
      }
      function rectOf(element) {
        const rect = element.getBoundingClientRect();
        return {
          x: rect.x,
          y: rect.y,
          top: rect.top,
          left: rect.left,
          right: rect.right,
          bottom: rect.bottom,
          width: rect.width,
          height: rect.height
        };
      }
      function cssEscape(value) {
        return String(value).replace(/[^a-zA-Z0-9_-]/g, function(ch) {
          return "\\" + ch.charCodeAt(0).toString(16) + " ";
        });
      }
      function selectorFor(element) {
        if (element.id) return "#" + cssEscape(element.id);
        const testId = element.getAttribute("data-testid") || element.getAttribute("data-test-id");
        if (testId) return element.tagName.toLowerCase() + "[data-testid=\"" + String(testId).replace(/"/g, "\\\"") + "\"]";
        const parts = [];
        let current = element;
        while (current && current.nodeType === 1 && parts.length < 5) {
          let part = current.tagName.toLowerCase();
          if (current.classList && current.classList.length > 0) {
            part += "." + Array.from(current.classList).slice(0, 2).map(cssEscape).join(".");
          }
          const parent = current.parentElement;
          if (parent) {
            const siblings = Array.from(parent.children).filter(function(child) { return child.tagName === current.tagName; });
            if (siblings.length > 1) part += ":nth-of-type(" + (siblings.indexOf(current) + 1) + ")";
          }
          parts.unshift(part);
          current = parent;
        }
        return parts.join(" > ");
      }
      function viewportPoint(rect) {
        return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
      }
      function anchorStateFor(element, event) {
        const rect = rectOf(element);
        const role = element.getAttribute("role") || element.tagName.toLowerCase();
        const text = textOf(element);
        return {
          anchor: {
            kind: "element",
            selector: selectorFor(element),
            role: role,
            text: text
          },
          framePath: [],
          frameUrl: location.href,
          viewportSize: { width: window.innerWidth, height: window.innerHeight },
          cardViewportRect: rect,
          markerViewportPoint: event ? { x: event.clientX, y: event.clientY } : viewportPoint(rect)
        };
      }
      function designEditorStateFor(element) {
        return {
          id: "appshot-bridge-design",
          selector: selectorFor(element),
          role: element.getAttribute("role") || element.tagName.toLowerCase(),
          text: textOf(element),
          rect: rectOf(element),
          declarations: []
        };
      }
      function closestImage(element) {
        if (!element) return null;
        if (element.tagName && element.tagName.toLowerCase() === "img") return element;
        if (typeof element.closest === "function") return element.closest("img");
        return null;
      }
      function imagePayload(img) {
        return {
          sourceUrl: img.currentSrc || img.src || "",
          alt: img.alt || "",
          selector: selectorFor(img),
          rect: rectOf(img),
          naturalSize: { width: img.naturalWidth || 0, height: img.naturalHeight || 0 }
        };
      }
      function ensureRuntimeEventLog() {
        if (!Array.isArray(window.__appshotRuntimeEventLog)) {
          window.__appshotRuntimeEventLog = [];
        }
        return window.__appshotRuntimeEventLog;
      }
      function pushRuntimeEvent(type, event, fields) {
        const element = elementFromEventTarget(event && event.target);
        const payload = Object.assign({
          type: type,
          source: appshotBridgeSource,
          bridgeEvent: true,
          candidate: false,
          capturedAt: new Date().toISOString(),
          pageUrl: location.href,
          title: document.title,
          anchorState: anchorStateFor(element, event || null)
        }, fields || {});
        const log = ensureRuntimeEventLog();
        log.push(payload);
        if (log.length > 200) {
          log.splice(0, log.length - 200);
        }
        return payload;
      }
      function installRuntimeBridge() {
        const log = ensureRuntimeEventLog();
        if (appshotClearBridgeLog) {
          log.splice(0, log.length);
        }
        window.__appshotRuntimeBridgeVersion = appshotBridgeVersion;
        if (!appshotInstallBridge) return;
        if (window.__appshotRuntimeBridgeInstalled) return;
        window.__appshotRuntimeBridgeInstalled = true;
        document.addEventListener("pointerdown", function(event) {
          const element = elementFromEventTarget(event.target);
          const anchorState = anchorStateFor(element, event);
          const commentId = "appshot-bridge-" + Date.now();
          pushRuntimeEvent("browser-sidebar-runtime-open-editor", event, {
            anchorState: anchorState,
            editorMode: event.altKey ? "design" : "comment",
            commentId: commentId
          });
          pushRuntimeEvent("browser-sidebar-runtime-create-comment-at-point", event, {
            point: { x: event.clientX, y: event.clientY },
            anchorState: anchorState,
            commentId: commentId
          });
          pushRuntimeEvent("browser-sidebar-runtime-update-anchor", event, {
            anchorState: anchorState,
            commentId: commentId
          });
        }, true);
        document.addEventListener("pointermove", function(event) {
          if (!event.altKey && !event.shiftKey) return;
          const element = elementFromEventTarget(event.target);
          const anchorState = anchorStateFor(element, event);
          const designEditorState = designEditorStateFor(element);
          pushRuntimeEvent("browser-sidebar-runtime-design-modifier-state", event, {
            isDesignModifierPressed: event.altKey
          });
          pushRuntimeEvent("browser-sidebar-runtime-design-scrub-changed", event, {
            anchorState: anchorState,
            designEditorState: designEditorState,
            designChange: designEditorState
          });
        }, true);
        document.addEventListener("dragstart", function(event) {
          const img = closestImage(elementFromEventTarget(event.target));
          if (!img) return;
          const image = imagePayload(img);
          if (!image.sourceUrl) return;
          pushRuntimeEvent("browser-sidebar-runtime-image-drag-started", event, {
            sourceUrl: image.sourceUrl,
            image: image
          });
        }, true);
        document.addEventListener("dragend", function(event) {
          const img = closestImage(elementFromEventTarget(event.target));
          if (!img) return;
          const image = imagePayload(img);
          if (!image.sourceUrl) return;
          pushRuntimeEvent("browser-sidebar-runtime-image-drag-ended", event, {
            sourceUrl: image.sourceUrl,
            image: image
          });
        }, true);
        document.addEventListener("keydown", function(event) {
          if (event.key !== "Alt" && event.key !== "Option") return;
          pushRuntimeEvent("browser-sidebar-runtime-design-modifier-state", event, {
            isDesignModifierPressed: true
          });
        }, true);
        document.addEventListener("keyup", function(event) {
          if (event.key !== "Alt" && event.key !== "Option") return;
          pushRuntimeEvent("browser-sidebar-runtime-design-modifier-state", event, {
            isDesignModifierPressed: false
          });
        }, true);
        pushRuntimeEvent("browser-sidebar-runtime-sync", null, {
          state: {
            type: "browser-sidebar-runtime-sync",
            interactionMode: "comment",
            annotationEditorMode: "comment",
            isAgentControllingBrowser: false,
            canUseTweaks: true,
            isDesignModifierPressed: false,
            isOriginalViewEnabled: false,
            isTweaksEditorOpen: false,
            comments: []
          }
        });
      }
      installRuntimeBridge();
      const viewportSize = { width: window.innerWidth, height: window.innerHeight };
      const images = Array.from(document.images).filter(function(img) {
        return Boolean(img.currentSrc || img.src);
      }).slice(0, 40).map(function(img, index) {
        return {
          index: index,
          sourceUrl: img.currentSrc || img.src,
          alt: img.alt || "",
          selector: selectorFor(img),
          text: textOf(img),
          rect: rectOf(img),
          naturalSize: { width: img.naturalWidth || 0, height: img.naturalHeight || 0 }
        };
      });
      const designSelector = "a,button,input,textarea,select,img,[role],[data-testid],h1,h2,h3,h4,p,main,nav,section,article";
      const designTargets = Array.from(document.querySelectorAll(designSelector)).filter(function(element) {
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      }).slice(0, 80).map(function(element, index) {
        return {
          index: index,
          tagName: element.tagName.toLowerCase(),
          role: element.getAttribute("role") || element.tagName.toLowerCase(),
          selector: selectorFor(element),
          text: textOf(element),
          rect: rectOf(element)
        };
      });
      const runtimeBridgeLog = ensureRuntimeEventLog();
      const runtimeBridge = {
        installed: Boolean(window.__appshotRuntimeBridgeInstalled),
        installRequested: appshotInstallBridge,
        clearRequested: appshotClearBridgeLog,
        liveEventStreamAvailable: Boolean(window.__appshotRuntimeBridgeInstalled),
        version: window.__appshotRuntimeBridgeVersion || appshotBridgeVersion,
        source: appshotBridgeSource,
        eventCount: runtimeBridgeLog.length,
        events: runtimeBridgeLog.slice(-80)
      };
      return {
        available: true,
        pageUrl: location.href,
        title: document.title,
        viewportSize: viewportSize,
        devicePixelRatio: window.devicePixelRatio || 1,
        images: images,
        designTargets: designTargets,
        runtimeBridge: runtimeBridge
      };
    })())
    """#
}

private func javaScriptStringLiteral(_ value: String) -> String {
    var out = "\""
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x22:
            out += "\\\""
        case 0x5C:
            out += "\\\\"
        case 0x0A:
            out += "\\n"
        case 0x0D:
            out += "\\r"
        case 0x09:
            out += "\\t"
        default:
            out.unicodeScalars.append(scalar)
        }
    }
    out += "\""
    return out
}

private func parseJSONObject(_ text: String) -> JSONObject? {
    parseJSONValue(text) as? JSONObject
}

private func parseJSONValue(_ text: String) -> Any? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = trimmed.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) else {
        return nil
    }
    return object
}

public func codexSummaryPayload(from payload: JSONObject, maxTreeLines: Int = 420) -> JSONObject {
    let text = codexSummaryText(from: payload, maxTreeLines: maxTreeLines)
    let accessibility = payload["accessibility"] as? JSONObject
    let root = accessibility?["root"] as? JSONObject
    let selectedLines = codexSelectedElementLines(from: root)
    let focusedLine = codexFocusedElementLine(from: accessibility)
    let textEvidenceLines = codexWindowTextEvidenceLines(from: payload)
    let browserPayload = payload["codexBrowserPayload"] as? JSONObject

    return [
        "format": "codex-appshot-text",
        "text": text,
        "treeLineCount": codexTreeLines(from: root, maxLines: maxTreeLines).count,
        "selectedLineCount": selectedLines.count,
        "textEvidenceLineCount": textEvidenceLines.count,
        "hasFocusedElement": focusedLine != nil,
        "hasBrowserPayload": browserPayload != nil,
        "browserPayloadFormat": codexTrimmedString(browserPayload?["format"]) ?? "none",
        "hasBrowserRuntimeState": payload["codexBrowserRuntimeState"] is JSONObject,
        "browserRuntimeStateFormat": codexTrimmedString((payload["codexBrowserRuntimeState"] as? JSONObject)?["format"]) ?? "none"
    ]
}

public func codexBrowserPayload(
    from payload: JSONObject,
    annotationScreenshotsMode: String = browserAnnotationScreenshotsModeNecessary
) -> JSONObject {
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
    let runtimeState = payload["codexBrowserRuntimeState"] as? JSONObject
    let browserDOMIntegration = payload["codexBrowserDOMIntegration"] as? JSONObject
    let electronRemoteDebugging = payload["codexElectronRemoteDebugging"] as? JSONObject
    let runtimeProtocol = (browserDOMIntegration?["browserRuntimeProtocol"] as? JSONObject)
        ?? (payload["codexBrowserRuntimeProtocol"] as? JSONObject)

    let appName = codexTrimmedString(app["localizedName"]) ?? codexTrimmedString(app["bundleIdentifier"]) ?? "Unknown"
    let bundleIdentifier = codexTrimmedString(app["bundleIdentifier"]) ?? ""
    let windowTitle = codexTrimmedString(window?["title"]) ?? codexTrimmedString(root?["title"]) ?? appName
    let domTarget = codexBrowserDOMPrimaryTarget(from: browserDOMIntegration)
    let domPageURL = codexTrimmedString(browserDOMIntegration?["pageUrl"])
    let pageURL = domPageURL ?? codexAppShotURL(bundleIdentifier: bundleIdentifier, appName: appName, windowTitle: windowTitle)
    let targetText = codexTrimmedString(domTarget?["text"])
    let nearbyText = codexBrowserNearbyText(
        accessibility: accessibility,
        domTitle: codexTrimmedString(browserDOMIntegration?["title"]),
        targetText: targetText
    )
    let documentContext = codexDocumentContext(from: accessibility)
    let targetSelector = codexTrimmedString(domTarget?["selector"])
        ?? (bundleIdentifier.isEmpty ? "app:\(appName)" : "bundle:\(bundleIdentifier)")
    let targetName = targetText ?? codexTrimmedString(root?["title"]) ?? windowTitle
    let targetDescription = codexTrimmedString(browserDOMIntegration?["title"]) ?? windowTitle
    let targetRole = codexTrimmedString(domTarget?["role"]) ?? codexTrimmedString(root?["role"]) ?? "AXWindow"

    var localBrowserContext: JSONObject = [
        "pageUrl": pageURL,
        "framePath": [],
        "frameUrl": pageURL,
        "targetDescription": targetDescription,
        "targetRole": targetRole,
        "targetName": targetName,
        "targetSelector": targetSelector,
        "targetPath": codexBrowserTargetPath(
            domTarget: domTarget,
            pageURL: pageURL,
            fallback: codexTargetPath(from: root, appName: appName, windowTitle: windowTitle)
        ),
        "nearbyText": nearbyText
    ]
    if let targetText {
        localBrowserContext["targetImmediateText"] = targetText
    }
    if !documentContext.isEmpty {
        localBrowserContext["documentContext"] = documentContext
    }

    var localBrowserCommentMetadata: JSONObject = [
        "kind": browserDOMIntegration == nil ? "appshot-native" : "browser",
        "bundleIdentifier": bundleIdentifier,
        "applicationName": appName,
        "windowTitle": windowTitle,
        "annotationScreenshotsMode": normalizedBrowserAnnotationScreenshotsMode(annotationScreenshotsMode)
    ]
    if let markerViewportPoint = codexBrowserDOMMarkerViewportPoint(from: browserDOMIntegration) {
        localBrowserCommentMetadata["markerViewportPoint"] = markerViewportPoint
    }
    if let viewportSize = codexBrowserDOMViewportSize(from: browserDOMIntegration) ?? codexViewportSize(from: window) {
        localBrowserCommentMetadata["viewportSize"] = viewportSize
    }
    if let windowID = window?["windowID"] {
        localBrowserCommentMetadata["windowID"] = windowID
    }
    if let runtimeState {
        localBrowserCommentMetadata["runtimeState"] = runtimeState
    }
    if let browserDOMIntegration {
        localBrowserCommentMetadata["browserDOMIntegration"] = [
            "available": browserDOMIntegration["available"] ?? false,
            "source": browserDOMIntegration["source"] ?? "",
            "imageCount": browserDOMIntegration["imageCount"] ?? 0,
            "designTargetCount": browserDOMIntegration["designTargetCount"] ?? 0,
            "browserRuntimeEventCount": browserDOMIntegration["browserRuntimeEventCount"] ?? 0,
            "browserRuntimeBridgeEventCount": browserDOMIntegration["browserRuntimeBridgeEventCount"] ?? 0,
            "browserRuntimeCandidateEventCount": browserDOMIntegration["browserRuntimeCandidateEventCount"] ?? 0,
            "liveEventStreamAvailable": browserDOMIntegration["liveEventStreamAvailable"] ?? false,
            "remoteDebuggingTarget": browserDOMIntegration["remoteDebuggingTarget"] ?? NSNull()
        ]
    }
    if let electronRemoteDebugging {
        localBrowserCommentMetadata["electronRemoteDebugging"] = codexElectronRemoteDebuggingSummary(electronRemoteDebugging)
    }

    let localBrowserDesignChange = codexBrowserLocalDesignChange(from: runtimeState)
    let localBrowserAttachedImages = browserDOMIntegration?["localBrowserAttachedImages"] as? [JSONObject] ?? []
    let localBrowserRuntimeEvents: Any = browserDOMIntegration?["browserRuntimeEvents"] ?? []
    let localBrowserScreenshot = codexBrowserLocalScreenshot(
        screenshot: screenshot,
        runtimeState: runtimeState
    )

    let out: JSONObject = [
        "format": "codex-browser-comment-payload-adapter",
        "source": "appshot-native-adapter",
        "type": "comment",
        "content": [
            [
                "content_type": "text",
                "text": codexSummaryBody(appName: appName, windowTitle: windowTitle, nearbyText: nearbyText)
            ]
        ],
        "position": [
            "side": "right",
            "path": codexBrowserPositionPath(pageURL: pageURL, title: targetDescription, fallback: windowTitle.isEmpty ? appName : windowTitle),
            "line": 1
        ],
        "localBrowserContext": localBrowserContext,
        "localBrowserCommentMetadata": localBrowserCommentMetadata,
        "localBrowserAttachedImages": localBrowserAttachedImages,
        "localBrowserDesignChange": localBrowserDesignChange,
        "localBrowserRuntimeState": runtimeState.map { $0 as Any } ?? NSNull(),
        "localBrowserRuntimeProtocol": runtimeProtocol.map { $0 as Any } ?? NSNull(),
        "localBrowserRuntimeEvents": localBrowserRuntimeEvents,
        "localBrowserScreenshot": localBrowserScreenshot
    ]
    return out
}

private func codexBrowserDOMPrimaryTarget(from integration: JSONObject?) -> JSONObject? {
    if let designTargets = integration?["designTargets"] as? [JSONObject],
       let first = designTargets.first {
        return first
    }
    if let events = integration?["browserRuntimeEvents"] as? [JSONObject] {
        for event in events {
            if let anchor = (event["anchorState"] as? JSONObject)?["anchor"] as? JSONObject {
                return [
                    "selector": codexTrimmedString(anchor["selector"]) ?? "",
                    "role": codexTrimmedString(anchor["role"]) ?? "",
                    "text": codexTrimmedString(anchor["text"]) ?? ""
                ]
            }
        }
    }
    return nil
}

private func codexBrowserNearbyText(
    accessibility: JSONObject?,
    domTitle: String?,
    targetText: String?
) -> String {
    let axText = codexNearbyText(from: accessibility)
    let domLines = [domTitle, targetText].compactMap { codexTrimmedString($0) }
    guard !domLines.isEmpty else {
        return axText
    }
    if axText.isEmpty {
        return domLines.joined(separator: "\n")
    }
    return (domLines + [axText]).joined(separator: "\n")
}

private func codexBrowserTargetPath(domTarget: JSONObject?, pageURL: String, fallback: Any) -> Any {
    if let elementPath = domTarget?["elementPath"] {
        return elementPath
    }
    if let selector = codexTrimmedString(domTarget?["selector"]) {
        return ["browser", pageURL, selector]
    }
    return fallback
}

private func codexBrowserDOMMarkerViewportPoint(from integration: JSONObject?) -> JSONObject? {
    if let events = integration?["browserRuntimeEvents"] as? [JSONObject] {
        for event in events {
            if let point = (event["anchorState"] as? JSONObject)?["markerViewportPoint"] as? JSONObject {
                return point
            }
            if let point = event["point"] as? JSONObject {
                return point
            }
        }
    }
    if let target = codexBrowserDOMPrimaryTarget(from: integration),
       let rect = target["rect"] as? JSONObject {
        return codexBrowserViewportPoint(from: rect)
    }
    return nil
}

private func codexBrowserDOMViewportSize(from integration: JSONObject?) -> JSONObject? {
    let viewport = integration?["viewportSize"] as? JSONObject
    guard let width = codexNumber(viewport?["width"]),
          let height = codexNumber(viewport?["height"]) else {
        return nil
    }
    return [
        "width": width,
        "height": height
    ]
}

private func codexBrowserLocalDesignChange(from runtimeState: JSONObject?) -> Any {
    guard let activeDesignChange = runtimeState?["activeDesignChange"] as? JSONObject else {
        return NSNull()
    }
    return ["group": activeDesignChange]
}

private func codexBrowserLocalScreenshot(screenshot: JSONObject?, runtimeState: JSONObject?) -> Any {
    guard var screenshotPayload = screenshot else {
        return NSNull()
    }
    if let activeDesignChange = runtimeState?["activeDesignChange"] as? JSONObject,
       let commentID = codexTrimmedString(activeDesignChange["id"]) {
        screenshotPayload["commentId"] = commentID
    }
    return screenshotPayload
}

private func codexBrowserPositionPath(pageURL: String, title: String, fallback: String) -> String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedTitle.isEmpty {
        return "browser:\(trimmedTitle)"
    }
    if let url = URL(string: pageURL),
       let host = url.host {
        let path = url.path == "/" ? "" : url.path
        return "browser:\(host)\(path)"
    }
    return "browser:\(fallback)"
}

private func codexAppShotURL(bundleIdentifier: String, appName: String, windowTitle: String) -> String {
    let identity = (bundleIdentifier.isEmpty ? appName : bundleIdentifier)
        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "unknown"
    let title = windowTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    return title.isEmpty ? "appshot://macos/\(identity)" : "appshot://macos/\(identity)?window=\(title)"
}

private func codexNearbyText(from accessibility: JSONObject?) -> String {
    for key in ["visibleText", "text"] {
        if let text = codexTrimmedString(accessibility?[key]) {
            let lines = codexPreviewTextLines(text, maxLines: 28, maxLineLength: 220)
            if !lines.isEmpty {
                return lines.joined(separator: "\n")
            }
        }
    }

    if let documents = accessibility?["documentReferences"] as? [JSONObject] {
        for document in documents {
            if let preview = codexTrimmedString(document["textPreview"]) {
                let lines = codexPreviewTextLines(preview, maxLines: 20, maxLineLength: 220)
                if !lines.isEmpty {
                    return lines.joined(separator: "\n")
                }
            }
        }
    }
    return ""
}

private func codexDocumentContext(from accessibility: JSONObject?) -> JSONObject {
    var context: JSONObject = [:]
    if let visibleText = codexTrimmedString(accessibility?["visibleText"]) {
        context["visibleText"] = codexPreviewTextLines(visibleText, maxLines: 36, maxLineLength: 220).joined(separator: "\n")
    }
    if let accessibilityText = codexTrimmedString(accessibility?["text"]) {
        context["accessibilityText"] = codexPreviewTextLines(accessibilityText, maxLines: 36, maxLineLength: 220).joined(separator: "\n")
    }
    if let documents = accessibility?["documentReferences"] as? [JSONObject] {
        let documentPayloads: [JSONObject] = documents.prefix(3).map { document in
            var out: JSONObject = [
                "path": codexTrimmedString(document["path"]) ?? codexTrimmedString(document["url"]) ?? "document",
                "textPreview": codexPreviewTextLines(
                    codexTrimmedString(document["textPreview"]) ?? "",
                    maxLines: 28,
                    maxLineLength: 220
                ).joined(separator: "\n")
            ]
            if let sizeBytes = document["sizeBytes"] {
                out["sizeBytes"] = sizeBytes
            }
            if let previewBytes = document["textPreviewBytes"] {
                out["textPreviewBytes"] = previewBytes
            }
            if let truncated = document["textTruncated"] {
                out["textTruncated"] = truncated
            }
            return out
        }
        if !documentPayloads.isEmpty {
            context["documents"] = documentPayloads
        }
    }
    return context.filter { entry in
        if let string = entry.value as? String {
            return !string.isEmpty
        }
        return true
    }
}

private func codexTargetPath(from root: JSONObject?, appName: String, windowTitle: String) -> Any {
    if let path = root?["path"] {
        return path
    }
    return ["macos", appName, windowTitle]
}

private func codexViewportSize(from window: JSONObject?) -> JSONObject? {
    guard let bounds = window?["bounds"] as? JSONObject,
          let width = codexNumber(bounds["width"]),
          let height = codexNumber(bounds["height"]) else {
        return nil
    }
    return [
        "width": width,
        "height": height
    ]
}

private func codexNumber(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber:
        return number.doubleValue
    case let value as Double:
        return value
    case let value as Float:
        return Double(value)
    case let value as Int:
        return Double(value)
    case let value as CGFloat:
        return Double(value)
    default:
        return nil
    }
}

private func codexSummaryBody(appName: String, windowTitle: String, nearbyText: String) -> String {
    var lines = ["AppShot capture for \(appName): \(windowTitle)"]
    if !nearbyText.isEmpty {
        lines.append("")
        lines.append(contentsOf: codexPreviewTextLines(nearbyText, maxLines: 18, maxLineLength: 220))
    }
    return lines.joined(separator: "\n")
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

    let textEvidenceLines = codexWindowTextEvidenceLines(from: payload)
    if !textEvidenceLines.isEmpty {
        lines.append("")
        lines.append("Window Text:")
        lines.append(contentsOf: textEvidenceLines)
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

    lines.append("</appshot>")
    return lines.joined(separator: "\n")
}

private func codexWindowTextEvidenceLines(from payload: JSONObject, maxLines: Int = 180) -> [String] {
    let accessibility = payload["accessibility"] as? JSONObject
    var sections: [(title: String, lines: [String])] = []

    if let documents = accessibility?["documentReferences"] as? [JSONObject] {
        for document in documents.prefix(3) {
            guard let text = codexTrimmedString(document["textPreview"]) else {
                continue
            }
            let path = codexTrimmedString(document["path"]) ?? codexTrimmedString(document["url"]) ?? "document"
            let previewLines = codexPreviewTextLines(text, maxLines: 90, maxLineLength: 260)
            guard !previewLines.isEmpty else {
                continue
            }

            var documentLines = previewLines
            if document["textTruncated"] as? Bool == true,
               let sizeBytes = document["sizeBytes"] as? Int,
               let previewBytes = document["textPreviewBytes"] as? Int,
               sizeBytes > previewBytes {
                documentLines.append("... document preview truncated at \(previewBytes) of \(sizeBytes) bytes")
            }
            sections.append(("Document: \(path)", documentLines))
        }
    }

    if let visibleText = codexTrimmedString(accessibility?["visibleText"]) {
        let visibleLines = codexPreviewTextLines(visibleText, maxLines: 70, maxLineLength: 220)
        if !visibleLines.isEmpty {
            sections.append(("Visible Text", visibleLines))
        }
    }

    if sections.isEmpty,
       let accessibilityText = codexTrimmedString(accessibility?["text"]) {
        let textLines = codexPreviewTextLines(accessibilityText, maxLines: 90, maxLineLength: 220)
        if !textLines.isEmpty {
            sections.append(("Accessibility Text", textLines))
        }
    }

    if let ocr = payload["ocr"] as? JSONObject,
       let ocrText = codexTrimmedString(ocr["text"]) {
        let ocrLines = codexPreviewTextLines(ocrText, maxLines: 70, maxLineLength: 220)
        if !ocrLines.isEmpty {
            sections.append(("OCR Text", ocrLines))
        }
    }

    var output: [String] = []
    var remaining = maxLines
    for section in sections where remaining > 0 {
        output.append("\t\(section.title):")
        remaining -= 1
        for line in section.lines {
            guard remaining > 0 else {
                break
            }
            output.append("\t\t\(line)")
            remaining -= 1
        }
    }
    if remaining == 0, !output.isEmpty {
        output.append("\t... window text evidence truncated")
    }
    return output
}

private func codexPreviewTextLines(_ text: String, maxLines: Int, maxLineLength: Int) -> [String] {
    let sourceLines = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    var lines: [String] = []
    var seen = Set<String>()
    var processedLineCount = 0
    for sourceLine in sourceLines {
        processedLineCount += 1
        let line = codexTruncatedTextLine(sourceLine, maxLength: maxLineLength)
        guard !seen.contains(line) else {
            continue
        }
        seen.insert(line)
        lines.append(line)
        if lines.count >= maxLines {
            break
        }
    }

    if sourceLines.count > processedLineCount {
        lines.append("... \(sourceLines.count - processedLineCount) more lines")
    }
    return lines
}

private func codexTruncatedTextLine(_ line: String, maxLength: Int) -> String {
    guard line.count > maxLength else {
        return line
    }
    let prefix = line.prefix(max(0, maxLength - 16))
    return "\(prefix)... [truncated]"
}

private func codexTreeLines(from root: JSONObject?, maxLines: Int) -> [String] {
    guard let root else {
        return []
    }

    var lines: [String] = []
    var seen = Set<String>()
    var seenStructuralLines = Set<String>()
    codexAppendElementLines(
        root,
        depth: 0,
        lines: &lines,
        maxLines: maxLines,
        seen: &seen,
        seenStructuralLines: &seenStructuralLines
    )
    return lines
}

private func codexAppendElementLines(
    _ element: JSONObject,
    depth: Int,
    lines: inout [String],
    maxLines: Int,
    seen: inout Set<String>,
    seenStructuralLines: inout Set<String>
) {
    guard lines.count < maxLines else {
        return
    }

    let digest = codexElementDigest(element)
    let line = codexElementLine(element)
    let dedupeStructuralLine = codexShouldDedupeStructuralLine(element, line: line)
    let structuralLineSeen = dedupeStructuralLine && seenStructuralLines.contains(line)
    let includeLine = codexShouldIncludeElementLine(element)
        && !seen.contains(digest)
        && !structuralLineSeen
        && (!codexIsStructuralShell(element) || codexHasUnseenRenderableDescendant(element, seen: seen))
    if includeLine {
        seen.insert(digest)
        if dedupeStructuralLine {
            seenStructuralLines.insert(line)
        }
        lines.append(String(repeating: "\t", count: depth) + line)
    }

    let children = codexChildrenForSummary(of: element)
    for child in children {
        guard lines.count < maxLines else {
            lines.append(String(repeating: "\t", count: includeLine ? depth + 1 : depth) + "... truncated")
            return
        }
        codexAppendElementLines(
            child,
            depth: includeLine ? depth + 1 : depth,
            lines: &lines,
            maxLines: maxLines,
            seen: &seen,
            seenStructuralLines: &seenStructuralLines
        )
    }
}

private func codexSelectedElementLines(from root: JSONObject?) -> [String] {
    guard let root else {
        return []
    }

    var lines: [String] = []
    var seen = Set<String>()
    codexVisitElements(root) { element in
        if codexIsSelected(element) {
            let line = codexElementLine(element)
            guard !seen.contains(line) else {
                return
            }
            seen.insert(line)
            lines.append(line)
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
    let value = codexDisplayValueString(element["value"])
    let textContent = codexTrimmedString(element["textContent"])
    let placeholder = codexTrimmedString(element["placeholderValue"])
    let identifier = codexTrimmedString(element["identifier"])
    let selectedText = codexTrimmedString(element["selectedText"])
    let url = codexURLString(element)

    let descendantLabel = ["row", "cell"].contains(role)
        ? codexPrimaryDescendantLabel(element)
        : nil
    let settableAnnotation = codexSettableAnnotation(element)

    if let settableAnnotation {
        parts.append(settableAnnotation)
    }

    if let title {
        parts.append(title)
    } else if ["text", "文本"].contains(role),
              let text = value ?? textContent ?? description {
        parts.append(text)
    } else if let description,
              codexShouldRenderDescription(role: role),
              settableAnnotation == nil || description != codexSettableValueString(element) {
        parts.append(codexDescriptionLabel(description, role: role))
    } else if let textContent {
        parts.append(textContent)
    } else if let descendantLabel {
        parts.append(descendantLabel)
    }

    if !["text", "文本"].contains(role),
       !codexSettableAnnotationConsumesValue(element),
       let value,
       value != title,
       value != description,
       value != textContent,
       codexShouldRenderValue(element) {
        if parts.count > 1, let last = parts.popLast() {
            parts.append("\(last), Value: \(value)")
        } else {
            parts.append("Value: \(value)")
        }
    }
    if let placeholder,
       settableAnnotation == nil || placeholder != codexSettableValueString(element) {
        parts.append("Placeholder: \(placeholder)")
    }
    if let selectedText, selectedText != title, selectedText != value {
        parts.append("SelectedText: \(selectedText)")
    }
    if let url {
        if parts.count > 1, let last = parts.popLast() {
            parts.append("\(last), URL: \(url)")
        } else {
            parts.append("URL: \(url)")
        }
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

private func codexURLString(_ element: JSONObject) -> String? {
    codexTrimmedString(element["url"]) ?? codexTrimmedString(element["document"])
}

private func codexShouldRenderDescription(role: String) -> Bool {
    let suppressedDescriptionRoles = Set([
        "button",
        "checkbox",
        "switch",
        "toggle button",
        "按钮",
        "复选框",
        "切换按钮",
        "转换"
    ])
    return !suppressedDescriptionRoles.contains(role)
}

private func codexDescriptionLabel(_ description: String, role: String) -> String {
    let rawDescriptionRoles = Set([
        "cell",
        "container",
        "list",
        "outline",
        "outline row",
        "pop up button",
        "row",
        "scroll area",
        "split group",
        "tab group",
        "toolbar",
        "单元格",
        "组",
        "内容列表",
        "列表",
        "大纲",
        "外框",
        "外框行",
        "滚动区",
        "分离组",
        "弹出式按钮",
        "标签组",
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
    let isExplicitlySettable = (element["settableAttributes"] as? [String])?.contains("value") == true
    let isImplicitSettable = codexIsImplicitSettableValueElement(element)
    guard isExplicitlySettable || isImplicitSettable else {
        return nil
    }

    guard let rawValue = codexSettableRawValue(element) else {
        if isExplicitlySettable,
           let value = element["value"] {
            return "(settable, \(codexValueTypeName(value)))"
        }
        return nil
    }

    if isImplicitSettable {
        return "(settable, integer)"
    }

    return "(settable, \(codexValueTypeName(rawValue))) \(codexScalarString(rawValue))"
}

private func codexSettableAnnotationConsumesValue(_ element: JSONObject) -> Bool {
    codexSettableAnnotation(element) != nil && !codexIsImplicitSettableValueElement(element)
}

private func codexIsImplicitSettableValueElement(_ element: JSONObject) -> Bool {
    let role = codexRoleName(element)
    guard ["radio button", "标签", "单选按钮"].contains(role),
          !codexIsSelected(element),
          codexSettableRawValue(element) != nil else {
        return false
    }
    return true
}

private func codexShouldRenderValue(_ element: JSONObject) -> Bool {
    ["radio button", "标签", "单选按钮"].contains(codexRoleName(element))
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
    if ["text field", "text area", "文本栏", "文本区域"].contains(codexRoleName(element)),
       let description = codexTrimmedString(element["description"]) {
        return description
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
    if value is Int {
        return "integer"
    }
    if let number = value as? NSNumber {
        let doubleValue = number.doubleValue
        return doubleValue.rounded() == doubleValue ? "integer" : "float"
    }
    if value is Double || value is Float || value is CGFloat {
        return "float"
    }
    return "value"
}

private func codexDisplayValueString(_ value: Any?) -> String? {
    if let string = codexTrimmedString(value) {
        return string
    }
    if let bool = value as? Bool {
        return bool ? "1" : "0"
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
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
       codexDisplayValueString(element["value"]) == nil,
       codexTrimmedString(element["identifier"]) == nil,
       element["truncatedByTimeout"] as? Bool == true {
        return false
    }

    if codexIsStructuralShell(element) {
        let childCount = codexSemanticChildren(of: element).count
        return childCount > 1
    }

    return true
}

private func codexIsStructuralShell(_ element: JSONObject) -> Bool {
    let role = codexRoleName(element)
    let structuralShellRoles = Set([
        "element",
        "application",
        "cell",
        "container",
        "content list",
        "group",
        "list",
        "outline",
        "scroll area",
        "tab group",
        "toolbar",
        "应用",
        "单元格",
        "内容列表",
        "外框",
        "工具栏",
        "滚动区",
        "组",
        "标签组",
        "列表"
    ])
    return structuralShellRoles.contains(role)
        && codexTrimmedString(element["title"]) == nil
        && codexTrimmedString(element["description"]) == nil
        && codexDisplayValueString(element["value"]) == nil
        && codexTrimmedString(element["textContent"]) == nil
        && codexTrimmedString(element["identifier"]) == nil
        && !codexIsSelected(element)
}

private func codexShouldDedupeStructuralLine(_ element: JSONObject, line: String) -> Bool {
    guard !codexIsSelected(element) else {
        return false
    }

    let role = codexRoleName(element)
    let dedupableStructuralRoles = Set([
        "cell",
        "container",
        "content list",
        "group",
        "HTML content",
        "list",
        "outline",
        "scroll area",
        "split group",
        "tab group",
        "toolbar",
        "web area",
        "HTML 内容",
        "单元格",
        "内容列表",
        "列表",
        "分离组",
        "外框",
        "工具栏",
        "滚动区",
        "组",
        "标签组"
    ])
    guard dedupableStructuralRoles.contains(role) else {
        return false
    }

    // Keep repeated unlabeled scroll/list/tab shells visible; Codex often shows
    // them as separate structural boundaries in macOS Settings and Xcode.
    let unlabeledLine = line == role
    if unlabeledLine {
        return ["container", "content list", "group", "toolbar", "内容列表", "工具栏", "组"].contains(role)
    }
    return true
}

private func codexHasUnseenRenderableDescendant(_ element: JSONObject, seen: Set<String>) -> Bool {
    for child in codexChildrenForSummary(of: element) {
        if codexShouldIncludeElementLine(child),
           !seen.contains(codexElementDigest(child)) {
            return true
        }
        if codexHasUnseenRenderableDescendant(child, seen: seen) {
            return true
        }
    }
    return false
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
    var out: [JSONObject] = []
    var seen = Set<String>()
    for key in ["visibleRows", "rows", "children", "childrenInNavigationOrder", "selectedChildren", "visibleChildren", "contents", "tabs", "splitters", "windows"] {
        guard let children = element[key] as? [JSONObject], !children.isEmpty else {
            continue
        }
        for child in children where !codexIsColumn(child) && !codexIsWindowChromeElement(child) {
            let identity = codexChildIdentity(child)
            guard !seen.contains(identity) else {
                continue
            }
            seen.insert(identity)
            out.append(child)
        }
    }
    return out
}

private func codexChildIdentity(_ element: JSONObject) -> String {
    let parts = [
        codexTrimmedString(element["role"]) ?? codexRoleName(element),
        codexTrimmedString(element["roleDescription"]) ?? "",
        codexTrimmedString(element["title"]) ?? "",
        codexTrimmedString(element["description"]) ?? "",
        codexDisplayValueString(element["value"]) ?? "",
        codexTrimmedString(element["textContent"]) ?? "",
        codexTrimmedString(element["identifier"]) ?? ""
    ]
    let hasDescriptivePayload = parts.dropFirst(2).contains { !$0.isEmpty }
    guard hasDescriptivePayload else {
        return codexTrimmedString(element["elementID"]) ?? parts.joined(separator: "|")
    }

    var descriptiveParts = parts
    if let position = element["position"] as? JSONObject {
        descriptiveParts.append("\(Int(numberValue(position["x"]) ?? 0))")
        descriptiveParts.append("\(Int(numberValue(position["y"]) ?? 0))")
    }
    if let size = element["size"] as? JSONObject {
        descriptiveParts.append("\(Int(numberValue(size["width"]) ?? 0))")
        descriptiveParts.append("\(Int(numberValue(size["height"]) ?? 0))")
    }
    return descriptiveParts.joined(separator: "|")
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
        if let valueText = codexDisplayValueString(value["value"]) ?? codexTrimmedString(value["textContent"]) {
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
        codexDisplayValueString(element["value"]) ?? "",
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
        case "AXGroup":
            return "container"
        case "AXStaticText":
            if let roleDescription = codexTrimmedString(element["roleDescription"]) {
                return roleDescription
            }
            return "text"
        default:
            break
        }
    }
    if let roleDescription = codexTrimmedString(element["roleDescription"]) {
        if ["group", "组"].contains(roleDescription) {
            return "container"
        }
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
