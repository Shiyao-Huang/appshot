import AppKit
#if canImport(AppShotCore)
import AppShotCore
#endif
import CoreGraphics
import SwiftUI

@main
struct AppShotDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppShotAppDelegate.self) private var appDelegate
    @StateObject private var model = AppShotModel()

    var body: some Scene {
        WindowGroup("AppShot") {
            AppShotDashboardView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 540)
                .onAppear {
                    model.refreshStatus()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.refreshStatus()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("AppShot", systemImage: model.menuBarSymbol) {
            MenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            AppShotSettingsView()
                .environmentObject(model)
        }
    }
}

final class AppShotAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// @sm:node appshot.app.status
// @sm:feature appshot.status-ui
// @sm:prev macos.menu-bar-extra
// @sm:next appshot.core.capture
// @sm:deps SwiftUI,AppShotCore,NSWorkspace
// @sm:evidence swift build && .build/debug/AppShotApp
@MainActor
final class AppShotModel: ObservableObject {
    private static let globalShortcutEnabledKey = "AppShot.globalShortcut.enabled"
    private static let browserAnnotationScreenshotsModeKey = "AppShot.browserAnnotationScreenshotsMode"
    private static let browserAnnotationEditorModeKey = "AppShot.browserAnnotationEditorMode"
    private static let browserOriginalViewEnabledKey = "AppShot.browserOriginalViewEnabled"
    private static let browserDesignModifierPressedKey = "AppShot.browserDesignModifierPressed"
    private static let browserTweaksEditorOpenKey = "AppShot.browserTweaksEditorOpen"
    private let optionShortcutMonitor = OptionPairShortcutMonitor()

    @Published var state: String = "checking"
    @Published var accessibility = false
    @Published var screenRecording = false
    @Published var permissionMode = "-"
    @Published var permissionExecutable = "-"
    @Published var frontmostName = "-"
    @Published var bundleIdentifier = "-"
    @Published var primaryWindowTitle = "-"
    @Published var windowCount = 0
    @Published var blockers: [String] = []
    @Published var advisories: [String] = []
    @Published var lastCaptureSummary = "No capture yet"
    @Published var captureCacheSummary = "Empty"
    @Published var lastJSON = "{}"
    @Published var lastError: String?
    @Published var isCapturing = false
    @Published var isRefreshing = false
    @Published var isGlobalShortcutEnabled: Bool = AppShotModel.defaultGlobalShortcutEnabled() {
        didSet {
            guard isGlobalShortcutEnabled != oldValue else {
                return
            }
            UserDefaults.standard.set(isGlobalShortcutEnabled, forKey: Self.globalShortcutEnabledKey)
            configureGlobalShortcut()
        }
    }
    @Published var browserAnnotationScreenshotsMode: String = AppShotModel.defaultBrowserAnnotationScreenshotsMode() {
        didSet {
            let normalized = normalizedBrowserAnnotationScreenshotsMode(browserAnnotationScreenshotsMode)
            if browserAnnotationScreenshotsMode != normalized {
                browserAnnotationScreenshotsMode = normalized
                return
            }
            guard browserAnnotationScreenshotsMode != oldValue else {
                return
            }
            UserDefaults.standard.set(browserAnnotationScreenshotsMode, forKey: Self.browserAnnotationScreenshotsModeKey)
        }
    }
    @Published var browserAnnotationEditorMode: String = AppShotModel.defaultBrowserAnnotationEditorMode() {
        didSet {
            let normalized = normalizedBrowserAnnotationEditorMode(browserAnnotationEditorMode)
            if browserAnnotationEditorMode != normalized {
                browserAnnotationEditorMode = normalized
                return
            }
            guard browserAnnotationEditorMode != oldValue else {
                return
            }
            UserDefaults.standard.set(browserAnnotationEditorMode, forKey: Self.browserAnnotationEditorModeKey)
        }
    }
    @Published var browserOriginalViewEnabled: Bool = AppShotModel.defaultBrowserOriginalViewEnabled() {
        didSet {
            guard browserOriginalViewEnabled != oldValue else {
                return
            }
            UserDefaults.standard.set(browserOriginalViewEnabled, forKey: Self.browserOriginalViewEnabledKey)
        }
    }
    @Published var browserDesignModifierPressed: Bool = AppShotModel.defaultBrowserDesignModifierPressed() {
        didSet {
            guard browserDesignModifierPressed != oldValue else {
                return
            }
            UserDefaults.standard.set(browserDesignModifierPressed, forKey: Self.browserDesignModifierPressedKey)
        }
    }
    @Published var browserTweaksEditorOpen: Bool = AppShotModel.defaultBrowserTweaksEditorOpen() {
        didSet {
            guard browserTweaksEditorOpen != oldValue else {
                return
            }
            UserDefaults.standard.set(browserTweaksEditorOpen, forKey: Self.browserTweaksEditorOpenKey)
        }
    }
    @Published var isAutoRefreshEnabled = false
    @Published var lastSampleAt: Date?
    @Published var samplingIntervalSeconds: Double = 2.0 {
        didSet {
            guard samplingIntervalSeconds != oldValue, isAutoRefreshEnabled else {
                return
            }
            startAutoRefreshTimer()
        }
    }
    @Published var frontAppTrail: [FrontAppTrailEntry] = []
    private var statusRequestSerial = 0
    private var captureRequestSerial = 0
    private var sampleRequestSerial = 0
    private var sampleInFlight = false
    private var autoRefreshTimer: Timer?

    init() {
        optionShortcutMonitor.onTrigger = { [weak self] in
            Task { @MainActor in
                self?.handleGlobalShortcut()
            }
        }
        configureGlobalShortcut()
    }

    var globalShortcutLabel: String {
        "Left Option + Right Option"
    }

    var menuBarSymbol: String {
        if isCapturing || isRefreshing {
            return "hourglass"
        }
        if lastError != nil {
            return "app.badge"
        }
        if accessibility && screenRecording {
            return "app.connected.to.app.below.fill"
        }
        return "app.dashed"
    }

    var statusTitle: String {
        if isCapturing {
            return "Capturing"
        }
        if isRefreshing {
            return "Refreshing"
        }
        if lastError != nil {
            return "Error"
        }
        if state == "ready" {
            return "Ready"
        }
        if state == "checking" {
            return "Checking"
        }
        return "Needs Attention"
    }

    func refreshStatus(prompt: Bool = false) {
        statusRequestSerial += 1
        let requestID = statusRequestSerial
        isRefreshing = true
        lastError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error>
            do {
                let payload = AppShotCore.status(prompt: prompt)
                result = .success(try AppShotCore.jsonString(payload, pretty: true))
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard requestID == self.statusRequestSerial else {
                    return
                }
                self.isRefreshing = false
                switch result {
                case .success(let json):
                    self.lastJSON = json
                    if let payload = Self.payload(from: json) {
                        self.applyStatus(payload, recordTrail: true)
                    }
                case .failure(let error):
                    self.lastError = String(describing: error)
                }
            }
        }
    }

    func requestPermissions() {
        refreshStatus(prompt: true)
        schedulePermissionRefreshes()
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        guard enabled != isAutoRefreshEnabled else {
            return
        }
        isAutoRefreshEnabled = enabled
        if enabled {
            sampleFrontApp()
            startAutoRefreshTimer()
        } else {
            autoRefreshTimer?.invalidate()
            autoRefreshTimer = nil
            sampleInFlight = false
        }
    }

    func setGlobalShortcutEnabled(_ enabled: Bool) {
        isGlobalShortcutEnabled = enabled
    }

    func setBrowserAnnotationScreenshotsMode(_ mode: String) {
        browserAnnotationScreenshotsMode = normalizedBrowserAnnotationScreenshotsMode(mode)
    }

    func setBrowserAnnotationEditorMode(_ mode: String) {
        browserAnnotationEditorMode = normalizedBrowserAnnotationEditorMode(mode)
    }

    func clearFrontAppTrail() {
        frontAppTrail.removeAll()
    }

    private func schedulePermissionRefreshes() {
        for delay in [1.0, 3.0, 8.0, 15.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshStatus()
            }
        }
    }

    private static func defaultGlobalShortcutEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: globalShortcutEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: globalShortcutEnabledKey)
    }

    private static func defaultBrowserAnnotationScreenshotsMode() -> String {
        normalizedBrowserAnnotationScreenshotsMode(UserDefaults.standard.string(forKey: browserAnnotationScreenshotsModeKey))
    }

    private static func defaultBrowserAnnotationEditorMode() -> String {
        normalizedBrowserAnnotationEditorMode(UserDefaults.standard.string(forKey: browserAnnotationEditorModeKey))
    }

    private static func defaultBrowserOriginalViewEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: browserOriginalViewEnabledKey)
    }

    private static func defaultBrowserDesignModifierPressed() -> Bool {
        UserDefaults.standard.bool(forKey: browserDesignModifierPressedKey)
    }

    private static func defaultBrowserTweaksEditorOpen() -> Bool {
        UserDefaults.standard.bool(forKey: browserTweaksEditorOpenKey)
    }

    private func configureGlobalShortcut() {
        if isGlobalShortcutEnabled {
            optionShortcutMonitor.start()
        } else {
            optionShortcutMonitor.stop()
        }
    }

    private func handleGlobalShortcut() {
        guard isGlobalShortcutEnabled, !isCapturing else {
            return
        }
        capture(
            includeScreenshot: true,
            includeOCR: false,
            preferRecentCache: false,
            writeCache: true,
            cacheTrigger: "left-right-option"
        )
    }

    private func startAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: samplingIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleFrontApp()
            }
        }
    }

    private func sampleFrontApp() {
        guard !isCapturing, !sampleInFlight else {
            return
        }
        sampleRequestSerial += 1
        let requestID = sampleRequestSerial
        sampleInFlight = true

        DispatchQueue.global(qos: .utility).async {
            let payload = AppShotCore.status(prompt: false)

            DispatchQueue.main.async {
                guard requestID == self.sampleRequestSerial else {
                    return
                }
                self.sampleInFlight = false
                self.applySample(payload)
            }
        }
    }

    func capture(
        includeScreenshot: Bool = true,
        includeOCR: Bool = false,
        preferRecentCache: Bool = false,
        writeCache: Bool = false,
        cacheTrigger: String? = nil
    ) {
        guard !isCapturing else {
            return
        }
        captureRequestSerial += 1
        let requestID = captureRequestSerial
        let browserAnnotationScreenshotsMode = self.browserAnnotationScreenshotsMode
        let browserAnnotationEditorMode = self.browserAnnotationEditorMode
        let browserOriginalViewEnabled = self.browserOriginalViewEnabled
        let browserDesignModifierPressed = self.browserDesignModifierPressed
        let browserTweaksEditorOpen = self.browserTweaksEditorOpen
        isCapturing = true
        lastError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error>
            do {
                let payload = try AppShotCore.capture(options: AppShotCaptureOptions(
                    includeScreenshot: includeScreenshot,
                    browserAnnotationScreenshotsMode: browserAnnotationScreenshotsMode,
                    browserAnnotationEditorMode: browserAnnotationEditorMode,
                    browserIsDesignModifierPressed: browserDesignModifierPressed,
                    browserIsOriginalViewEnabled: browserOriginalViewEnabled,
                    browserIsTweaksEditorOpen: browserTweaksEditorOpen,
                    maxDepth: 60,
                    maxChildren: 240,
                    includeOCR: includeOCR,
                    accessibilityTimeoutSeconds: 20.0,
                    screenshotTimeoutSeconds: 3.0,
                    preferRecentCache: preferRecentCache,
                    writeCache: writeCache,
                    cacheMaxAgeSeconds: 15.0,
                    cacheTrigger: cacheTrigger
                ))
                result = .success(try AppShotCore.jsonString(payload, pretty: true))
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard requestID == self.captureRequestSerial else {
                    return
                }
                self.isCapturing = false
                switch result {
                case .success(let json):
                    self.lastJSON = json
                    if let payload = Self.payload(from: json) {
                        self.applyCapture(payload)
                    }
                case .failure(let error):
                    self.lastError = String(describing: error)
                    self.refreshStatus()
                }
            }
        }
    }

    private static func payload(from json: String) -> JSONObject? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? JSONObject else {
            return nil
        }
        return payload
    }

    private func applyStatus(_ payload: JSONObject, recordTrail: Bool) {
        assignIfChanged(&state, payload["state"] as? String ?? "unknown")
        assignIfChanged(&blockers, payload["blockers"] as? [String] ?? [])
        assignIfChanged(&advisories, payload["advisories"] as? [String] ?? [])
        assignIfChanged(&windowCount, payload["windowCount"] as? Int ?? 0)
        assignIfChanged(&captureCacheSummary, Self.captureCacheSummary(from: payload["captureCache"] as? JSONObject))

        if let permissions = payload["permissions"] as? JSONObject {
            assignIfChanged(&accessibility, permissions["accessibility"] as? Bool ?? false)
            assignIfChanged(&screenRecording, permissions["screenRecording"] as? Bool ?? false)
            applyPermissionDetails(permissions)
        }
        if let app = payload["frontmostApplication"] as? JSONObject {
            assignIfChanged(&frontmostName, app["localizedName"] as? String ?? "-")
            assignIfChanged(&bundleIdentifier, app["bundleIdentifier"] as? String ?? "-")
        } else {
            assignIfChanged(&frontmostName, "-")
            assignIfChanged(&bundleIdentifier, "-")
        }
        if let window = payload["primaryWindow"] as? JSONObject {
            let title = window["title"] as? String ?? ""
            assignIfChanged(&primaryWindowTitle, title.isEmpty ? "(untitled window)" : title)
        } else {
            assignIfChanged(&primaryWindowTitle, "(no visible window)")
        }
        if recordTrail {
            appendFrontAppSample(from: payload)
        }
    }

    private func applySample(_ payload: JSONObject) {
        assignIfChanged(&windowCount, payload["windowCount"] as? Int ?? 0)

        if let app = payload["frontmostApplication"] as? JSONObject {
            assignIfChanged(&frontmostName, app["localizedName"] as? String ?? "-")
            assignIfChanged(&bundleIdentifier, app["bundleIdentifier"] as? String ?? "-")
        } else {
            assignIfChanged(&frontmostName, "-")
            assignIfChanged(&bundleIdentifier, "-")
        }

        if let window = payload["primaryWindow"] as? JSONObject {
            let title = window["title"] as? String ?? ""
            assignIfChanged(&primaryWindowTitle, title.isEmpty ? "(untitled window)" : title)
        } else {
            assignIfChanged(&primaryWindowTitle, "(no visible window)")
        }

        appendFrontAppSample(from: payload)
        lastSampleAt = Date()
    }

    private func applyCapture(_ payload: JSONObject) {
        if let permissions = payload["permissions"] as? JSONObject {
            accessibility = permissions["accessibility"] as? Bool ?? false
            screenRecording = permissions["screenRecording"] as? Bool ?? false
            applyPermissionDetails(permissions)
            advisories = Self.permissionAdvisories(from: permissions)
        }
        if let app = payload["frontmostApplication"] as? JSONObject {
            frontmostName = app["localizedName"] as? String ?? "-"
            bundleIdentifier = app["bundleIdentifier"] as? String ?? "-"
        } else {
            frontmostName = "-"
            bundleIdentifier = "-"
        }
        let windows = payload["windows"] as? [JSONObject] ?? []
        windowCount = windows.count
        captureCacheSummary = Self.captureCacheSummary(from: payload["captureCache"] as? JSONObject)
        if let window = payload["primaryWindow"] as? JSONObject {
            let title = window["title"] as? String ?? ""
            primaryWindowTitle = title.isEmpty ? "(untitled window)" : title
        } else {
            primaryWindowTitle = "(no visible window)"
        }
        let accessibilityPayload = payload["accessibility"] as? JSONObject
        let axLineCount = accessibilityPayload?["textLineCount"] as? Int
        let axSuffix = axLineCount.map { " with Accessibility text: \($0) lines" } ?? ""
        if let screenshot = payload["screenshot"] as? JSONObject,
           let captured = screenshot["captured"] as? Bool,
           let path = screenshot["path"] as? String {
            lastCaptureSummary = captured ? "Captured screenshot: \(path)\(axSuffix)" : "Capture ran but screenshot failed"
        } else {
            lastCaptureSummary = "Captured app context without screenshot"
        }
        if captureCacheSummary != "Empty" {
            lastCaptureSummary += " | Cache: \(captureCacheSummary)"
        }
        blockers = []
        state = accessibility && screenRecording ? "ready" : "needsAttention"
        appendFrontAppSample(from: payload)
    }

    private func appendFrontAppSample(from payload: JSONObject) {
        guard let app = payload["frontmostApplication"] as? JSONObject else {
            return
        }
        let window = payload["primaryWindow"] as? JSONObject
        let entry = FrontAppTrailEntry(
            firstSeen: Date(),
            lastSeen: Date(),
            sampleCount: 1,
            appName: app["localizedName"] as? String ?? "-",
            bundleIdentifier: app["bundleIdentifier"] as? String ?? "-",
            processIdentifier: app["processIdentifier"] as? Int ?? 0,
            windowTitle: {
                let title = window?["title"] as? String ?? ""
                return title.isEmpty ? "(no visible window)" : title
            }(),
            windowID: window?["windowID"] as? Int
        )

        if let first = frontAppTrail.first, first.dedupeKey == entry.dedupeKey {
            frontAppTrail[0].lastSeen = entry.lastSeen
            frontAppTrail[0].sampleCount += 1
        } else {
            frontAppTrail.insert(entry, at: 0)
            if frontAppTrail.count > 80 {
                frontAppTrail.removeLast(frontAppTrail.count - 80)
            }
        }
    }

    private func applyPermissionDetails(_ permissions: JSONObject) {
        if let stability = permissions["stability"] as? JSONObject {
            assignIfChanged(&permissionMode, stability["mode"] as? String ?? "-")
            let executable = stability["currentExecutablePath"] as? String ?? "-"
            assignIfChanged(&permissionExecutable, executable)
        } else {
            assignIfChanged(&permissionMode, "-")
            assignIfChanged(&permissionExecutable, "-")
        }
    }

    private static func permissionAdvisories(from permissions: JSONObject) -> [String] {
        guard let stability = permissions["stability"] as? JSONObject,
              let warning = stability["warning"] as? String,
              !warning.isEmpty else {
            return []
        }
        return [warning]
    }

    private static func captureCacheSummary(from cache: JSONObject?) -> String {
        guard let cache else {
            return "Empty"
        }
        if cache["available"] as? Bool == false {
            return "Empty"
        }

        let age = (cache["ageSeconds"] as? Double).map { "\($0)s" }
            ?? (cache["ageSeconds"] as? Int).map { "\($0)s" }
        let trigger = cache["trigger"] as? String
        let suffix = [
            trigger.map { "via \($0)" },
            age
        ].compactMap { $0 }.joined(separator: ", ")

        if let hit = cache["hit"] as? Bool {
            let reason = cache["reason"] as? String
            if hit {
                return suffix.isEmpty ? "Hit" : "Hit, \(suffix)"
            }
            if reason == "written" {
                return suffix.isEmpty ? "Updated" : "Updated, \(suffix)"
            }
            if let reason, reason != "miss" {
                return "Bypassed, \(reason)"
            }
            return "Miss"
        }

        if cache["recent"] as? Bool == true {
            return suffix.isEmpty ? "Recent" : "Recent, \(suffix)"
        }
        return suffix.isEmpty ? "Stale" : "Stale, \(suffix)"
    }

    private func assignIfChanged<T: Equatable>(_ value: inout T, _ nextValue: T) {
        guard value != nextValue else {
            return
        }
        value = nextValue
    }
}

@MainActor
final class OptionPairShortcutMonitor {
    private let leftOptionKeyCode: CGKeyCode = 58
    private let rightOptionKeyCode: CGKeyCode = 61
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var chordIsDown = false

    var onTrigger: (() -> Void)?

    func start() {
        guard globalMonitor == nil, localMonitor == nil else {
            return
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let keyCode = CGKeyCode(event.keyCode)
            Task { @MainActor in
                self?.handle(keyCode: keyCode)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(keyCode: CGKeyCode(event.keyCode))
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        chordIsDown = false
    }

    private func handle(keyCode: CGKeyCode) {
        guard keyCode == leftOptionKeyCode || keyCode == rightOptionKeyCode else {
            return
        }

        let leftIsDown = CGEventSource.keyState(.hidSystemState, key: leftOptionKeyCode)
        let rightIsDown = CGEventSource.keyState(.hidSystemState, key: rightOptionKeyCode)
        let nextChordIsDown = leftIsDown && rightIsDown

        if nextChordIsDown && !chordIsDown {
            chordIsDown = true
            onTrigger?()
        } else if !nextChordIsDown {
            chordIsDown = false
        }
    }
}

struct FrontAppTrailEntry: Identifiable {
    let id = UUID()
    var firstSeen: Date
    var lastSeen: Date
    var sampleCount: Int
    var appName: String
    var bundleIdentifier: String
    var processIdentifier: Int
    var windowTitle: String
    var windowID: Int?

    var dedupeKey: String {
        [
            bundleIdentifier,
            String(processIdentifier),
            String(windowID ?? 0),
            windowTitle
        ].joined(separator: "|")
    }

    var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        if Calendar.current.isDate(firstSeen, equalTo: lastSeen, toGranularity: .second) {
            return formatter.string(from: firstSeen)
        }
        return "\(formatter.string(from: firstSeen)) - \(formatter.string(from: lastSeen))"
    }
}

struct AppShotDashboardView: View {
    @EnvironmentObject private var model: AppShotModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusGrid
                    actions
                    samplerControls
                    frontAppTrail
                    blockers
                    jsonPreview
                }
                .padding(22)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: model.menuBarSymbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(model.state == "ready" ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("AppShot")
                    .font(.title2.weight(.semibold))
                Text(model.statusTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refreshStatus()
            } label: {
                Label(model.isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing || model.isCapturing)
        }
        .padding(22)
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                StatusTile(title: "Accessibility", value: model.accessibility ? "On" : "Off", symbol: "accessibility", good: model.accessibility)
                StatusTile(title: "Screen Recording", value: model.screenRecording ? "On" : "Off", symbol: "rectangle.on.rectangle", good: model.screenRecording)
            }
            GridRow {
                StatusTile(title: "Front App", value: model.frontmostName, symbol: "macwindow", good: model.frontmostName != "-")
                StatusTile(title: "Windows", value: String(model.windowCount), symbol: "rectangle.stack", good: model.windowCount > 0)
            }
            GridRow {
                StatusTile(title: "Bundle", value: model.bundleIdentifier, symbol: "shippingbox", good: model.bundleIdentifier != "-")
                StatusTile(title: "Primary Window", value: model.primaryWindowTitle, symbol: "rectangle.inset.filled", good: model.primaryWindowTitle != "-")
            }
            GridRow {
                StatusTile(title: "Permission Identity", value: model.permissionMode, symbol: "person.crop.rectangle.stack", good: model.permissionMode == "stableInstalledApp")
                StatusTile(title: "Permission Executable", value: model.permissionExecutable, symbol: "terminal", good: model.permissionExecutable.hasSuffix("/Applications/AppShot.app/Contents/MacOS/AppShot"))
            }
            GridRow {
                StatusTile(title: "Shortcut", value: model.isGlobalShortcutEnabled ? model.globalShortcutLabel : "Off", symbol: "keyboard", good: model.isGlobalShortcutEnabled)
                StatusTile(title: "Shortcut Cache", value: model.captureCacheSummary, symbol: "tray.and.arrow.down", good: model.captureCacheSummary != "Empty")
            }
            GridRow {
                StatusTile(title: "Browser Screenshots", value: model.browserAnnotationScreenshotsMode, symbol: "rectangle.on.rectangle.angled", good: true)
                Color.clear.frame(height: 0)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.requestPermissions()
            } label: {
                Label("Request Permissions", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRefreshing || model.isCapturing)

            Button {
                model.capture(includeScreenshot: true)
            } label: {
                Label(model.isCapturing ? "Capturing" : "Capture AppShot", systemImage: "camera.viewfinder")
            }
            .disabled(model.isCapturing)

            Button {
                model.capture(includeScreenshot: false, includeOCR: false)
            } label: {
                Label("Capture JSON", systemImage: "curlybraces")
            }
            .disabled(model.isCapturing)
        }
    }

    private var samplerControls: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { model.isAutoRefreshEnabled },
                set: { model.setAutoRefreshEnabled($0) }
            )) {
                Label("Auto Refresh", systemImage: "clock.arrow.circlepath")
            }
            .toggleStyle(.switch)

            Picker("Sample", selection: $model.samplingIntervalSeconds) {
                Text("1s").tag(1.0)
                Text("2s").tag(2.0)
                Text("5s").tag(5.0)
                Text("10s").tag(10.0)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Spacer()

            Text("\(model.frontAppTrail.reduce(0) { $0 + $1.sampleCount }) samples")
                .foregroundStyle(.secondary)

            Button {
                model.clearFrontAppTrail()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(model.frontAppTrail.isEmpty)
        }
    }

    private var frontAppTrail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Front App Trail")
                    .font(.headline)
                Spacer()
                Text(model.isAutoRefreshEnabled ? "Live" : "Paused")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(model.isAutoRefreshEnabled ? .green : .secondary)
            }

            if model.frontAppTrail.isEmpty {
                Text("No samples yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 6) {
                    ForEach(model.frontAppTrail.prefix(12)) { entry in
                        FrontAppTrailRow(entry: entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var blockers: some View {
        if let error = model.lastError {
            InfoPanel(title: "Error", symbol: "exclamationmark.triangle", color: .red, lines: [error])
        } else if !model.blockers.isEmpty {
            InfoPanel(title: "Needs Attention", symbol: "info.circle", color: .orange, lines: model.blockers)
        } else if !model.advisories.isEmpty {
            InfoPanel(title: "Advisory", symbol: "exclamationmark.shield", color: .orange, lines: model.advisories)
        } else {
            InfoPanel(title: "Last Capture", symbol: "checkmark.circle", color: .green, lines: [model.lastCaptureSummary])
        }
    }

    private var jsonPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current State JSON")
                .font(.headline)
            ScrollView(.horizontal) {
                Text(model.lastJSON)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 180, maxHeight: 260)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var model: AppShotModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: model.menuBarSymbol)
                Text("AppShot")
                    .font(.headline)
                Spacer()
                Text(model.statusTitle)
                    .foregroundStyle(.secondary)
            }
            Divider()
            StatusLine(label: "Accessibility", value: model.accessibility ? "On" : "Off", good: model.accessibility)
            StatusLine(label: "Screen Recording", value: model.screenRecording ? "On" : "Off", good: model.screenRecording)
            StatusLine(label: "Front App", value: model.frontmostName, good: model.frontmostName != "-")
            StatusLine(label: "Auto Refresh", value: model.isAutoRefreshEnabled ? "\(Int(model.samplingIntervalSeconds))s" : "Off", good: model.isAutoRefreshEnabled)
            StatusLine(label: "Shortcut", value: model.isGlobalShortcutEnabled ? model.globalShortcutLabel : "Off", good: model.isGlobalShortcutEnabled)
            StatusLine(label: "Cache", value: model.captureCacheSummary, good: model.captureCacheSummary != "Empty")
            HStack {
                Button("Refresh") {
                    model.refreshStatus()
                }
                .disabled(model.isRefreshing || model.isCapturing)
                Button("Permissions") {
                    model.requestPermissions()
                }
                .disabled(model.isRefreshing || model.isCapturing)
                Button("Capture") {
                    model.capture(includeScreenshot: true)
                }
                .disabled(model.isCapturing)
                Button(model.isAutoRefreshEnabled ? "Pause" : "Auto") {
                    model.setAutoRefreshEnabled(!model.isAutoRefreshEnabled)
                }
            }
        }
        .padding(14)
        .frame(width: 360)
        .onAppear {
            model.refreshStatus()
        }
    }
}

struct AppShotSettingsView: View {
    @EnvironmentObject private var model: AppShotModel

    var body: some View {
        Form {
            Toggle(isOn: Binding(
                get: { model.isGlobalShortcutEnabled },
                set: { model.setGlobalShortcutEnabled($0) }
            )) {
                Label("Global Shortcut", systemImage: "keyboard")
            }

            LabeledContent("Shortcut") {
                Text(model.globalShortcutLabel)
                    .font(.body.monospacedDigit())
            }

            LabeledContent("Shortcut Cache") {
                Text(model.captureCacheSummary)
            }

            Text("Press both Option keys together to capture into the shared CLI and MCP cache.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Browser Screenshots", selection: Binding(
                get: { model.browserAnnotationScreenshotsMode },
                set: { model.setBrowserAnnotationScreenshotsMode($0) }
            )) {
                Text("Necessary").tag(browserAnnotationScreenshotsModeNecessary)
                Text("Always").tag(browserAnnotationScreenshotsModeAlways)
            }
            .pickerStyle(.segmented)

            Picker("Browser Editor", selection: Binding(
                get: { model.browserAnnotationEditorMode },
                set: { model.setBrowserAnnotationEditorMode($0) }
            )) {
                Text("Comment").tag(browserAnnotationEditorModeComment)
                Text("Design").tag(browserAnnotationEditorModeDesign)
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $model.browserOriginalViewEnabled) {
                Label("Original View", systemImage: "rectangle.lefthalf.inset.filled")
            }

            Toggle(isOn: $model.browserDesignModifierPressed) {
                Label("Design Modifier", systemImage: "option")
            }

            Toggle(isOn: $model.browserTweaksEditorOpen) {
                Label("Tweaks Editor", systemImage: "slider.horizontal.3")
            }

            Divider()

            Button {
                model.requestPermissions()
            } label: {
                Label("Request Permissions", systemImage: "lock.open")
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct FrontAppTrailRow: View {
    let entry: FrontAppTrailEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "app.badge")
                .frame(width: 22)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.appName)
                        .font(.callout.weight(.medium))
                    Text("x\(entry.sampleCount)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(entry.windowTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(entry.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(entry.timeRange)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusTile: View {
    let title: String
    let value: String
    let symbol: String
    let good: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(good ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusLine: View {
    let label: String
    let value: String
    let good: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(good ? .green : .orange)
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

struct InfoPanel: View {
    let title: String
    let symbol: String
    let color: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(color)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
