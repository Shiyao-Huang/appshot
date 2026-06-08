import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum AppShotRuleStoreError: Error, CustomStringConvertible {
    case openFailed(String)
    case sqlite(String)
    case invalidRule(String)
    case invalidJSON(String)
    case missingSample(String)
    case readFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let path):
            return "Failed to open AppShot rules database at \(path)."
        case .sqlite(let message):
            return "SQLite error: \(message)"
        case .invalidRule(let message):
            return "Invalid AppShot rule: \(message)"
        case .invalidJSON(let message):
            return "Invalid JSON: \(message)"
        case .missingSample(let id):
            return "No AppShot training sample found with id \(id)."
        case .readFailed(let path):
            return "Failed to read \(path)."
        }
    }
}

public struct AppShotRuleStore {
    public static func defaultDatabasePath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("AppShot", isDirectory: true)
            .appendingPathComponent("rules.sqlite")
            .path
    }

    public static func initialize(databasePath: String? = nil) throws -> JSONObject {
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        return [
            "schemaVersion": 1,
            "databasePath": store.path,
            "tables": [
                "rules",
                "rule_versions",
                "rule_strategy_buckets",
                "rule_strategy_bucket_apps",
                "rule_change_events",
                "capture_samples",
                "sample_anchors",
                "rule_evaluations",
                "rule_run_outputs",
                "rule_run_metrics",
                "rule_improvement_pool"
            ]
        ]
    }

    public static func upsertRule(databasePath: String? = nil, ruleJSONText: String) throws -> JSONObject {
        let rule = try parseRule(ruleJSONText)
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        return try store.upsertRule(rule)
    }

    public static func listRules(databasePath: String? = nil, appBundleIdentifier: String? = nil) throws -> JSONObject {
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        return [
            "databasePath": store.path,
            "rules": try store.listRules(appBundleIdentifier: appBundleIdentifier)
        ]
    }

    public static func deleteRule(databasePath: String? = nil, id: String) throws -> JSONObject {
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        let deleted = try store.deleteRule(id: id)
        return [
            "databasePath": store.path,
            "id": id,
            "deleted": deleted
        ]
    }

    public static func patchRule(databasePath: String? = nil, id: String, patchJSONText: String) throws -> JSONObject {
        let patch = try parseJSONObjectStrict(patchJSONText)
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        guard let existing = try store.ruleJSON(id: id) else {
            throw AppShotRuleStoreError.invalidRule("no rule exists with id \(id)")
        }
        var merged = deepMerged(existing, patch)
        merged["id"] = id
        let result = try store.upsertRule(merged)
        try store.recordRuleChange(
            ruleID: id,
            version: result["version"] as? Int,
            action: "patch",
            reason: nil,
            payload: patch
        )
        return result
    }

    public static func setRuleEnabled(
        databasePath: String? = nil,
        id: String,
        enabled: Bool,
        reason: String?
    ) throws -> JSONObject {
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        return try store.setRuleEnabled(id: id, enabled: enabled, reason: reason)
    }

    public static func selectStrategy(
        databasePath: String? = nil,
        bucketID: String,
        ruleID: String,
        version: Int
    ) throws -> JSONObject {
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        return try store.selectStrategy(bucketID: bucketID, ruleID: ruleID, version: version)
    }

    public static func measure(
        databasePath: String? = nil,
        sampleID: String? = nil,
        appBundleIdentifier: String? = nil,
        bucketID: String? = nil,
        limit: Int = 50
    ) throws -> JSONObject {
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        return try store.measure(sampleID: sampleID, appBundleIdentifier: appBundleIdentifier, bucketID: bucketID, limit: limit)
    }

    public static func history(
        databasePath: String? = nil,
        id: String? = nil,
        bucketID: String? = nil,
        limit: Int = 50
    ) throws -> JSONObject {
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        return try store.history(ruleID: id, bucketID: bucketID, limit: limit)
    }

    public static func improvements(
        databasePath: String? = nil,
        status: String? = nil,
        appBundleIdentifier: String? = nil,
        bucketID: String? = nil,
        limit: Int = 50
    ) throws -> JSONObject {
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        return try store.improvements(status: status, appBundleIdentifier: appBundleIdentifier, bucketID: bucketID, limit: limit)
    }

    public static func recordSample(
        databasePath: String? = nil,
        sampleID: String?,
        appBundleIdentifier: String?,
        windowTitle: String?,
        screenshotPath: String?,
        captureJSONPath: String?,
        codexTextPath: String?,
        anchors: [String],
        anchorJSONText: String? = nil,
        notes: String?
    ) throws -> JSONObject {
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        let id = sampleID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? UUID().uuidString
        var anchorRecords: [AnchorInput] = []
        if let anchorJSONText, !anchorJSONText.isEmpty {
            anchorRecords = try parseAnchorRecords(anchorJSONText)
        }
        try store.recordSample(
            id: id,
            appBundleIdentifier: appBundleIdentifier,
            windowTitle: windowTitle,
            screenshotPath: screenshotPath,
            captureJSONPath: captureJSONPath,
            codexTextPath: codexTextPath,
            anchors: anchors,
            anchorRecords: anchorRecords,
            notes: notes
        )
        return [
            "databasePath": store.path,
            "sampleID": id,
            "anchorCount": anchors.count + anchorRecords.count
        ]
    }

    private static func parseAnchorRecords(_ text: String) throws -> [AnchorInput] {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw AppShotRuleStoreError.invalidJSON("--anchor-json must be a JSON array of {regex,source,required,weight}")
        }
        return array.compactMap { item in
            guard let obj = item as? JSONObject,
                  let regex = (obj["regex"] as? String) ?? (obj["anchor"] as? String),
                  !regex.isEmpty else { return nil }
            let source = (obj["source"] as? String) ?? "expected"
            let required = (obj["required"] as? Bool) ?? true
            let weight = (obj["weight"] as? Double) ?? ((obj["weight"] as? Int).map(Double.init)) ?? 1.0
            return AnchorInput(regex: regex, source: source, required: required, weight: weight)
        }
    }

    public static func evaluate(
        databasePath: String? = nil,
        sampleID: String,
        ruleID: String? = nil,
        corpus: String = "codex",
        outputTextPath: String? = nil,
        ruleJSONText: String? = nil,
        metricWeights: JSONObject? = nil
    ) throws -> JSONObject {
        let store = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
        try store.initialize()
        var rule: JSONObject? = nil
        if let ruleJSONText, !ruleJSONText.isEmpty {
            rule = try parseRule(ruleJSONText)
        }
        return try store.evaluate(
            sampleID: sampleID,
            ruleID: ruleID,
            corpus: corpus,
            outputTextPath: outputTextPath,
            rule: rule,
            metricWeights: metricWeights
        )
    }

    /// Apply a single rule to a capture JSON and return the Accessibility (student)
    /// output plus its TOON transport. OCR is always excluded from the output: it is a
    /// training-time teacher only, and the consuming agent reads pixels itself.
    public static func applyRule(
        databasePath: String? = nil,
        ruleJSONText: String? = nil,
        ruleID: String? = nil,
        captureJSONPath: String? = nil,
        sampleID: String? = nil,
        outputPath: String? = nil
    ) throws -> JSONObject {
        var store: AppShotRuleDatabase?
        func sharedStore() throws -> AppShotRuleDatabase {
            if let store { return store }
            let opened = try AppShotRuleDatabase(path: resolvedDatabasePath(databasePath))
            try opened.initialize()
            store = opened
            return opened
        }

        let rule: JSONObject
        if let ruleJSONText, !ruleJSONText.isEmpty {
            rule = try parseRule(ruleJSONText)
        } else if let ruleID, !ruleID.isEmpty {
            guard let stored = try sharedStore().ruleJSON(id: ruleID) else {
                throw AppShotRuleStoreError.invalidRule("no rule found with id \(ruleID)")
            }
            rule = stored
        } else {
            throw AppShotRuleStoreError.invalidRule("rules apply requires --rule-json, --rule-json-file, or --rule-id")
        }

        var capturePath = captureJSONPath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        if capturePath == nil, let sampleID, !sampleID.isEmpty {
            guard let sample = try sharedStore().sampleRow(id: sampleID),
                  let path = (sample["captureJSONPath"] as? String)?.nonEmpty else {
                throw AppShotRuleStoreError.missingSample(sampleID)
            }
            capturePath = path
        }
        guard let capturePath else {
            throw AppShotRuleStoreError.invalidJSON("rules apply requires --capture-json or --sample-id")
        }
        let captureText = try readText(capturePath)
        guard let capture = parseJSONObject(captureText) else {
            throw AppShotRuleStoreError.invalidJSON("capture JSON at \(capturePath) is not a JSON object")
        }
        let result = applyRuleToCapture(rule: rule, capture: capture)
        if let outputPath, let outNonEmpty = outputPath.nonEmpty,
           let text = result["text"] as? String {
            let expanded = (outNonEmpty as NSString).expandingTildeInPath
            try? text.write(toFile: expanded, atomically: true, encoding: .utf8)
        }
        var payload = result
        payload["capturePath"] = capturePath
        payload["ruleID"] = (rule["id"] as? String) ?? NSNull()
        return payload
    }

    private static func resolvedDatabasePath(_ databasePath: String?) -> String {
        databasePath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? defaultDatabasePath()
    }

    private static func parseRule(_ text: String) throws -> JSONObject {
        guard let data = text.data(using: .utf8) else {
            throw AppShotRuleStoreError.invalidJSON("rule JSON is not valid UTF-8")
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AppShotRuleStoreError.invalidJSON(error.localizedDescription)
        }
        guard let rule = value as? JSONObject else {
            throw AppShotRuleStoreError.invalidRule("top-level value must be a JSON object")
        }
        guard let id = (rule["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else {
            throw AppShotRuleStoreError.invalidRule("missing string id")
        }
        return rule
    }

    private static func parseJSONObjectStrict(_ text: String) throws -> JSONObject {
        guard let data = text.data(using: .utf8) else {
            throw AppShotRuleStoreError.invalidJSON("JSON is not valid UTF-8")
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AppShotRuleStoreError.invalidJSON(error.localizedDescription)
        }
        guard let object = value as? JSONObject else {
            throw AppShotRuleStoreError.invalidJSON("top-level value must be a JSON object")
        }
        return object
    }
}

private final class AppShotRuleDatabase {
    let path: String
    private let db: OpaquePointer?

    init(path: String) throws {
        self.path = (path as NSString).expandingTildeInPath
        let directory = (self.path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(self.path, &handle) == SQLITE_OK, let handle else {
            throw AppShotRuleStoreError.openFailed(self.path)
        }
        self.db = handle
    }

    deinit {
        sqlite3_close(db)
    }

    func initialize() throws {
        try exec("""
        PRAGMA foreign_keys = ON;
        CREATE TABLE IF NOT EXISTS rules (
            id TEXT PRIMARY KEY,
            app_bundle_id TEXT,
            scope TEXT NOT NULL DEFAULT 'global',
            window_title_regex TEXT,
            tree_regex TEXT,
            action_json TEXT NOT NULL DEFAULT '{}',
            rule_json TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            priority INTEGER NOT NULL DEFAULT 0,
            confidence REAL NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS rule_versions (
            version_id INTEGER PRIMARY KEY AUTOINCREMENT,
            rule_id TEXT NOT NULL,
            version INTEGER NOT NULL,
            rule_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(rule_id) REFERENCES rules(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS capture_samples (
            id TEXT PRIMARY KEY,
            app_bundle_id TEXT,
            window_title TEXT,
            screenshot_path TEXT,
            capture_json_path TEXT,
            codex_text_path TEXT,
            captured_at TEXT NOT NULL,
            notes TEXT
        );
        CREATE TABLE IF NOT EXISTS sample_anchors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sample_id TEXT NOT NULL,
            anchor_regex TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT 'expected',
            required INTEGER NOT NULL DEFAULT 1,
            weight REAL NOT NULL DEFAULT 1.0,
            FOREIGN KEY(sample_id) REFERENCES capture_samples(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS rule_strategy_buckets (
            bucket_id TEXT PRIMARY KEY,
            app_bundle_id TEXT NOT NULL,
            name TEXT NOT NULL,
            description TEXT,
            selected_rule_id TEXT,
            selected_rule_version INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS rule_strategy_bucket_apps (
            bucket_id TEXT NOT NULL,
            app_bundle_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY(bucket_id, app_bundle_id),
            FOREIGN KEY(bucket_id) REFERENCES rule_strategy_buckets(bucket_id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS rule_change_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rule_id TEXT,
            version INTEGER,
            action TEXT NOT NULL,
            actor TEXT NOT NULL DEFAULT 'agent',
            reason TEXT,
            payload_json TEXT NOT NULL DEFAULT '{}',
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS rule_run_outputs (
            run_id TEXT PRIMARY KEY,
            sample_id TEXT NOT NULL,
            rule_id TEXT NOT NULL,
            rule_version INTEGER NOT NULL,
            bucket_id TEXT,
            app_bundle_id TEXT,
            output_path TEXT,
            output_preview TEXT,
            output_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(sample_id) REFERENCES capture_samples(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS rule_run_metrics (
            run_id TEXT PRIMARY KEY,
            sample_id TEXT NOT NULL,
            rule_id TEXT NOT NULL,
            rule_version INTEGER NOT NULL,
            bucket_id TEXT,
            score REAL NOT NULL,
            anchor_recall REAL NOT NULL,
            baseline_recall REAL NOT NULL,
            improvement REAL NOT NULL,
            matched_anchors INTEGER NOT NULL,
            total_anchors INTEGER NOT NULL,
            missing_anchors_json TEXT NOT NULL,
            metric_json TEXT NOT NULL,
            evaluated_at TEXT NOT NULL,
            FOREIGN KEY(run_id) REFERENCES rule_run_outputs(run_id) ON DELETE CASCADE,
            FOREIGN KEY(sample_id) REFERENCES capture_samples(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS rule_improvement_pool (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sample_id TEXT NOT NULL,
            rule_id TEXT,
            rule_version INTEGER,
            bucket_id TEXT,
            app_bundle_id TEXT,
            severity INTEGER NOT NULL DEFAULT 1,
            status TEXT NOT NULL DEFAULT 'open',
            reason TEXT NOT NULL,
            recommendation TEXT NOT NULL,
            evidence_json TEXT NOT NULL DEFAULT '{}',
            created_at TEXT NOT NULL,
            FOREIGN KEY(sample_id) REFERENCES capture_samples(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS rule_evaluations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rule_id TEXT,
            sample_id TEXT NOT NULL,
            corpus TEXT NOT NULL DEFAULT 'codex',
            score REAL NOT NULL,
            anchor_recall REAL NOT NULL,
            matched_anchors INTEGER NOT NULL,
            total_anchors INTEGER NOT NULL,
            missing_anchors_json TEXT NOT NULL,
            evaluated_at TEXT NOT NULL,
            FOREIGN KEY(rule_id) REFERENCES rules(id) ON DELETE SET NULL,
            FOREIGN KEY(sample_id) REFERENCES capture_samples(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_rules_app ON rules(app_bundle_id);
        CREATE INDEX IF NOT EXISTS idx_sample_anchors_sample ON sample_anchors(sample_id);
        CREATE INDEX IF NOT EXISTS idx_rule_evaluations_sample ON rule_evaluations(sample_id);
        CREATE INDEX IF NOT EXISTS idx_rule_run_metrics_bucket ON rule_run_metrics(bucket_id);
        CREATE INDEX IF NOT EXISTS idx_rule_improvement_pool_status ON rule_improvement_pool(status, app_bundle_id);
        CREATE INDEX IF NOT EXISTS idx_rule_change_events_rule ON rule_change_events(rule_id, created_at);
        """)
        try addColumnIfMissing(table: "rule_evaluations", column: "corpus", definition: "TEXT NOT NULL DEFAULT 'codex'")
        try addColumnIfMissing(table: "rule_evaluations", column: "metric_json", definition: "TEXT")
        try addColumnIfMissing(table: "sample_anchors", column: "weight", definition: "REAL NOT NULL DEFAULT 1.0")
    }

    func upsertRule(_ rule: JSONObject) throws -> JSONObject {
        let id = try requiredString(rule["id"], field: "id")
        let match = rule["match"] as? JSONObject
        let action = rule["action"] as? JSONObject ?? [:]
        let appBundleID = firstString(match?["appBundleIds"]) ?? firstString(match?["appBundleId"]) ?? firstString(rule["appBundleId"])
        let scope = firstString(rule["scope"]) ?? (appBundleID == nil ? "global" : "app")
        let windowTitleRegex = firstString(match?["windowTitleRegex"]) ?? firstString(match?["titleRegex"])
        let treeRegex = firstString(match?["treeRegex"]) ?? firstString(match?["roleRegex"])
        let enabled = boolValue(rule["enabled"], defaultValue: true) ? 1 : 0
        let priority = intValue(rule["priority"], defaultValue: 0)
        let confidence = doubleValue(rule["confidence"], defaultValue: 0)
        let ruleJSON = try jsonString(rule)
        let actionJSON = try jsonString(action)
        let timestamp = now()
        let version = (try scalarInt("SELECT COALESCE(MAX(version), 0) + 1 FROM rule_versions WHERE rule_id = ?", [id])) ?? 1
        let exists = ((try scalarInt("SELECT COUNT(*) FROM rules WHERE id = ?", [id])) ?? 0) > 0

        try run("""
        INSERT INTO rules (
            id, app_bundle_id, scope, window_title_regex, tree_regex, action_json,
            rule_json, enabled, priority, confidence, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            app_bundle_id = excluded.app_bundle_id,
            scope = excluded.scope,
            window_title_regex = excluded.window_title_regex,
            tree_regex = excluded.tree_regex,
            action_json = excluded.action_json,
            rule_json = excluded.rule_json,
            enabled = excluded.enabled,
            priority = excluded.priority,
            confidence = excluded.confidence,
            updated_at = excluded.updated_at
        """, [
            id,
            appBundleID,
            scope,
            windowTitleRegex,
            treeRegex,
            actionJSON,
            ruleJSON,
            enabled,
            priority,
            confidence,
            timestamp,
            timestamp
        ])
        try run("INSERT INTO rule_versions (rule_id, version, rule_json, created_at) VALUES (?, ?, ?, ?)", [
            id,
            version,
            ruleJSON,
            timestamp
        ])
        try recordRuleChange(
            ruleID: id,
            version: version,
            action: exists ? "upsert" : "create",
            reason: nil,
            payload: ["rule": rule]
        )
        return [
            "databasePath": path,
            "id": id,
            "version": version,
            "created": !exists,
            "updated": exists
        ]
    }

    func listRules(appBundleIdentifier: String?) throws -> [JSONObject] {
        let sql: String
        let params: [Any?]
        if let appBundleIdentifier, !appBundleIdentifier.isEmpty {
            sql = """
            SELECT id, app_bundle_id, scope, window_title_regex, tree_regex, enabled, priority, confidence, updated_at, rule_json
            FROM rules
            WHERE app_bundle_id IS NULL OR app_bundle_id = ?
            ORDER BY priority DESC, id ASC
            """
            params = [appBundleIdentifier]
        } else {
            sql = """
            SELECT id, app_bundle_id, scope, window_title_regex, tree_regex, enabled, priority, confidence, updated_at, rule_json
            FROM rules
            ORDER BY priority DESC, id ASC
            """
            params = []
        }
        return try query(sql, params) { statement in
            [
                "id": columnString(statement, 0) ?? "",
                "appBundleId": columnString(statement, 1) ?? NSNull(),
                "scope": columnString(statement, 2) ?? "global",
                "windowTitleRegex": columnString(statement, 3) ?? NSNull(),
                "treeRegex": columnString(statement, 4) ?? NSNull(),
                "enabled": sqlite3_column_int(statement, 5) != 0,
                "priority": Int(sqlite3_column_int(statement, 6)),
                "confidence": sqlite3_column_double(statement, 7),
                "updatedAt": columnString(statement, 8) ?? "",
                "rule": parseJSONObject(columnString(statement, 9) ?? "{}") ?? [:]
            ]
        }
    }

    func deleteRule(id: String) throws -> Bool {
        let changesBefore = sqlite3_total_changes(db)
        try run("DELETE FROM rules WHERE id = ?", [id])
        let deleted = sqlite3_total_changes(db) > changesBefore
        if deleted {
            try recordRuleChange(ruleID: id, version: nil, action: "delete", reason: nil, payload: [:])
        }
        return deleted
    }

    func ruleJSON(id: String) throws -> JSONObject? {
        let rows: [JSONObject] = try query("SELECT rule_json FROM rules WHERE id = ?", [id]) { statement in
            parseJSONObject(columnString(statement, 0) ?? "{}") ?? [:]
        }
        return rows.first
    }

    func setRuleEnabled(id: String, enabled: Bool, reason: String?) throws -> JSONObject {
        let exists = ((try scalarInt("SELECT COUNT(*) FROM rules WHERE id = ?", [id])) ?? 0) > 0
        guard exists else {
            throw AppShotRuleStoreError.invalidRule("no rule exists with id \(id)")
        }
        let timestamp = now()
        try run("UPDATE rules SET enabled = ?, updated_at = ? WHERE id = ?", [enabled ? 1 : 0, timestamp, id])
        let version = try scalarInt("SELECT MAX(version) FROM rule_versions WHERE rule_id = ?", [id])
        try recordRuleChange(
            ruleID: id,
            version: version,
            action: enabled ? "activate" : "archive",
            reason: reason,
            payload: ["enabled": enabled]
        )
        return [
            "databasePath": path,
            "id": id,
            "enabled": enabled,
            "version": version ?? NSNull(),
            "reason": reason ?? NSNull()
        ]
    }

    func selectStrategy(bucketID: String, ruleID: String, version: Int) throws -> JSONObject {
        let appBundleID = try query("SELECT app_bundle_id FROM rules WHERE id = ?", [ruleID]) { statement in
            columnString(statement, 0)
        }.compactMap { $0 }.first ?? ""
        let timestamp = now()
        try run("""
        INSERT INTO rule_strategy_buckets (
            bucket_id, app_bundle_id, name, description, selected_rule_id,
            selected_rule_version, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(bucket_id) DO UPDATE SET
            selected_rule_id = excluded.selected_rule_id,
            selected_rule_version = excluded.selected_rule_version,
            updated_at = excluded.updated_at
        """, [
            bucketID,
            appBundleID,
            bucketID,
            "Selected by agent rule governance interface.",
            ruleID,
            version,
            timestamp,
            timestamp
        ])
        if !appBundleID.isEmpty {
            try run("""
            INSERT OR IGNORE INTO rule_strategy_bucket_apps (bucket_id, app_bundle_id, created_at)
            VALUES (?, ?, ?)
            """, [bucketID, appBundleID, timestamp])
        }
        try recordRuleChange(
            ruleID: ruleID,
            version: version,
            action: "select",
            reason: "selected for bucket \(bucketID)",
            payload: ["bucketID": bucketID]
        )
        return [
            "databasePath": path,
            "bucketID": bucketID,
            "selectedRuleID": ruleID,
            "selectedRuleVersion": version,
            "appBundleID": appBundleID
        ]
    }

    func measure(sampleID: String?, appBundleIdentifier: String?, bucketID: String?, limit: Int) throws -> JSONObject {
        var whereParts: [String] = []
        var params: [Any?] = []
        if let sampleID, !sampleID.isEmpty {
            whereParts.append("m.sample_id = ?")
            params.append(sampleID)
        }
        if let appBundleIdentifier, !appBundleIdentifier.isEmpty {
            whereParts.append("s.app_bundle_id = ?")
            params.append(appBundleIdentifier)
        }
        if let bucketID, !bucketID.isEmpty {
            whereParts.append("m.bucket_id = ?")
            params.append(bucketID)
        }
        let whereSQL = whereParts.isEmpty ? "" : "WHERE " + whereParts.joined(separator: " AND ")
        params.append(max(1, limit))
        let runRows: [JSONObject] = try query("""
        SELECT
            m.bucket_id,
            m.rule_id,
            m.rule_version,
            COUNT(*) AS sample_count,
            AVG(m.score) AS avg_score,
            AVG(m.anchor_recall) AS avg_anchor_recall,
            AVG(m.baseline_recall) AS avg_baseline_recall,
            AVG(m.improvement) AS avg_improvement,
            MAX(m.evaluated_at) AS last_evaluated_at
        FROM rule_run_metrics m
        JOIN capture_samples s ON s.id = m.sample_id
        \(whereSQL)
        GROUP BY m.bucket_id, m.rule_id, m.rule_version
        ORDER BY avg_score DESC, avg_anchor_recall DESC, sample_count DESC
        LIMIT ?
        """, params) { statement in
            [
                "bucketID": columnString(statement, 0) ?? NSNull(),
                "ruleID": columnString(statement, 1) ?? "",
                "ruleVersion": Int(sqlite3_column_int(statement, 2)),
                "sampleCount": Int(sqlite3_column_int(statement, 3)),
                "avgScore": sqlite3_column_double(statement, 4),
                "avgAnchorRecall": sqlite3_column_double(statement, 5),
                "avgBaselineRecall": sqlite3_column_double(statement, 6),
                "avgImprovement": sqlite3_column_double(statement, 7),
                "lastEvaluatedAt": columnString(statement, 8) ?? NSNull(),
                "source": "rule_run_metrics"
            ]
        }
        var evaluationWhereParts: [String] = []
        var evaluationParams: [Any?] = []
        if let sampleID, !sampleID.isEmpty {
            evaluationWhereParts.append("e.sample_id = ?")
            evaluationParams.append(sampleID)
        }
        if let appBundleIdentifier, !appBundleIdentifier.isEmpty {
            evaluationWhereParts.append("s.app_bundle_id = ?")
            evaluationParams.append(appBundleIdentifier)
        }
        if let bucketID, !bucketID.isEmpty {
            evaluationWhereParts.append("b.bucket_id = ?")
            evaluationParams.append(bucketID)
        }
        let evaluationWhereSQL = evaluationWhereParts.isEmpty ? "" : "WHERE " + evaluationWhereParts.joined(separator: " AND ")
        evaluationParams.append(max(1, limit))
        let evaluationRows: [JSONObject] = try query("""
        SELECT
            b.bucket_id,
            e.rule_id,
            COUNT(*) AS sample_count,
            AVG(e.score) AS avg_score,
            AVG(e.anchor_recall) AS avg_anchor_recall,
            MAX(e.evaluated_at) AS last_evaluated_at
        FROM rule_evaluations e
        JOIN capture_samples s ON s.id = e.sample_id
        LEFT JOIN rule_strategy_buckets b ON b.selected_rule_id = e.rule_id
        \(evaluationWhereSQL)
        GROUP BY b.bucket_id, e.rule_id
        ORDER BY avg_score DESC, avg_anchor_recall DESC, sample_count DESC
        LIMIT ?
        """, evaluationParams) { statement in
            [
                "bucketID": columnString(statement, 0) ?? NSNull(),
                "ruleID": columnString(statement, 1) ?? NSNull(),
                "ruleVersion": NSNull(),
                "sampleCount": Int(sqlite3_column_int(statement, 2)),
                "avgScore": sqlite3_column_double(statement, 3),
                "avgAnchorRecall": sqlite3_column_double(statement, 4),
                "avgBaselineRecall": NSNull(),
                "avgImprovement": NSNull(),
                "lastEvaluatedAt": columnString(statement, 5) ?? NSNull(),
                "source": "rule_evaluations"
            ]
        }
        let rows = (runRows + evaluationRows).sorted {
            let leftScore = doubleValue($0["avgScore"], defaultValue: 0)
            let rightScore = doubleValue($1["avgScore"], defaultValue: 0)
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            return doubleValue($0["avgAnchorRecall"], defaultValue: 0) > doubleValue($1["avgAnchorRecall"], defaultValue: 0)
        }.prefix(max(1, limit)).map { $0 }
        return [
            "databasePath": path,
            "filters": [
                "sampleID": jsonNullable(sampleID),
                "appBundleID": jsonNullable(appBundleIdentifier),
                "bucketID": jsonNullable(bucketID)
            ],
            "measurements": rows
        ]
    }

    func history(ruleID: String?, bucketID: String?, limit: Int) throws -> JSONObject {
        let boundedLimit = max(1, limit)
        let versions: [JSONObject]
        if let ruleID, !ruleID.isEmpty {
            versions = try query("""
            SELECT rule_id, version, rule_json, created_at
            FROM rule_versions
            WHERE rule_id = ?
            ORDER BY version DESC
            LIMIT ?
            """, [ruleID, boundedLimit]) { statement in
                [
                    "ruleID": columnString(statement, 0) ?? "",
                    "version": Int(sqlite3_column_int(statement, 1)),
                    "rule": parseJSONObject(columnString(statement, 2) ?? "{}") ?? [:],
                    "createdAt": columnString(statement, 3) ?? ""
                ]
            }
        } else {
            versions = try query("""
            SELECT rule_id, version, rule_json, created_at
            FROM rule_versions
            ORDER BY created_at DESC
            LIMIT ?
            """, [boundedLimit]) { statement in
                [
                    "ruleID": columnString(statement, 0) ?? "",
                    "version": Int(sqlite3_column_int(statement, 1)),
                    "rule": parseJSONObject(columnString(statement, 2) ?? "{}") ?? [:],
                    "createdAt": columnString(statement, 3) ?? ""
                ]
            }
        }

        var metricWhere: [String] = []
        var metricParams: [Any?] = []
        if let ruleID, !ruleID.isEmpty {
            metricWhere.append("rule_id = ?")
            metricParams.append(ruleID)
        }
        if let bucketID, !bucketID.isEmpty {
            metricWhere.append("bucket_id = ?")
            metricParams.append(bucketID)
        }
        let metricSQL = metricWhere.isEmpty ? "" : "WHERE " + metricWhere.joined(separator: " AND ")
        metricParams.append(boundedLimit)
        let metrics: [JSONObject] = try query("""
        SELECT run_id, sample_id, rule_id, rule_version, bucket_id, score,
               anchor_recall, baseline_recall, improvement, evaluated_at
        FROM rule_run_metrics
        \(metricSQL)
        ORDER BY evaluated_at DESC
        LIMIT ?
        """, metricParams) { statement in
            [
                "runID": columnString(statement, 0) ?? "",
                "sampleID": columnString(statement, 1) ?? "",
                "ruleID": columnString(statement, 2) ?? "",
                "ruleVersion": Int(sqlite3_column_int(statement, 3)),
                "bucketID": columnString(statement, 4) ?? NSNull(),
                "score": sqlite3_column_double(statement, 5),
                "anchorRecall": sqlite3_column_double(statement, 6),
                "baselineRecall": sqlite3_column_double(statement, 7),
                "improvement": sqlite3_column_double(statement, 8),
                "evaluatedAt": columnString(statement, 9) ?? ""
            ]
        }

        var eventWhere: [String] = []
        var eventParams: [Any?] = []
        if let ruleID, !ruleID.isEmpty {
            eventWhere.append("rule_id = ?")
            eventParams.append(ruleID)
        }
        let eventSQL = eventWhere.isEmpty ? "" : "WHERE " + eventWhere.joined(separator: " AND ")
        eventParams.append(boundedLimit)
        let events: [JSONObject] = try query("""
        SELECT rule_id, version, action, actor, reason, payload_json, created_at
        FROM rule_change_events
        \(eventSQL)
        ORDER BY created_at DESC, id DESC
        LIMIT ?
        """, eventParams) { statement in
            [
                "ruleID": columnString(statement, 0) ?? NSNull(),
                "version": sqlite3_column_type(statement, 1) == SQLITE_NULL ? NSNull() : Int(sqlite3_column_int(statement, 1)),
                "action": columnString(statement, 2) ?? "",
                "actor": columnString(statement, 3) ?? "",
                "reason": columnString(statement, 4) ?? NSNull(),
                "payload": parseJSONObject(columnString(statement, 5) ?? "{}") ?? [:],
                "createdAt": columnString(statement, 6) ?? ""
            ]
        }

        return [
            "databasePath": path,
            "filters": [
                "ruleID": jsonNullable(ruleID),
                "bucketID": jsonNullable(bucketID)
            ],
            "versions": versions,
            "events": events,
            "metrics": metrics,
            "improvements": try improvementsRows(status: nil, appBundleIdentifier: nil, bucketID: bucketID, ruleID: ruleID, limit: boundedLimit)
        ]
    }

    func improvements(status: String?, appBundleIdentifier: String?, bucketID: String?, limit: Int) throws -> JSONObject {
        [
            "databasePath": path,
            "improvements": try improvementsRows(
                status: status,
                appBundleIdentifier: appBundleIdentifier,
                bucketID: bucketID,
                ruleID: nil,
                limit: max(1, limit)
            )
        ]
    }

    func recordRuleChange(ruleID: String?, version: Int?, action: String, reason: String?, payload: JSONObject) throws {
        try run("""
        INSERT INTO rule_change_events (rule_id, version, action, actor, reason, payload_json, created_at)
        VALUES (?, ?, ?, 'agent', ?, ?, ?)
        """, [
            ruleID,
            version,
            action,
            reason,
            try jsonString(payload),
            now()
        ])
    }

    private func improvementsRows(
        status: String?,
        appBundleIdentifier: String?,
        bucketID: String?,
        ruleID: String?,
        limit: Int
    ) throws -> [JSONObject] {
        var whereParts: [String] = []
        var params: [Any?] = []
        if let status, !status.isEmpty {
            whereParts.append("status = ?")
            params.append(status)
        }
        if let appBundleIdentifier, !appBundleIdentifier.isEmpty {
            whereParts.append("app_bundle_id = ?")
            params.append(appBundleIdentifier)
        }
        if let bucketID, !bucketID.isEmpty {
            whereParts.append("bucket_id = ?")
            params.append(bucketID)
        }
        if let ruleID, !ruleID.isEmpty {
            whereParts.append("rule_id = ?")
            params.append(ruleID)
        }
        let whereSQL = whereParts.isEmpty ? "" : "WHERE " + whereParts.joined(separator: " AND ")
        params.append(max(1, limit))
        return try query("""
        SELECT id, sample_id, rule_id, rule_version, bucket_id, app_bundle_id,
               severity, status, reason, recommendation, evidence_json, created_at
        FROM rule_improvement_pool
        \(whereSQL)
        ORDER BY severity DESC, created_at DESC
        LIMIT ?
        """, params) { statement in
            [
                "id": Int(sqlite3_column_int(statement, 0)),
                "sampleID": columnString(statement, 1) ?? "",
                "ruleID": columnString(statement, 2) ?? NSNull(),
                "ruleVersion": sqlite3_column_type(statement, 3) == SQLITE_NULL ? NSNull() : Int(sqlite3_column_int(statement, 3)),
                "bucketID": columnString(statement, 4) ?? NSNull(),
                "appBundleID": columnString(statement, 5) ?? NSNull(),
                "severity": Int(sqlite3_column_int(statement, 6)),
                "status": columnString(statement, 7) ?? "",
                "reason": columnString(statement, 8) ?? "",
                "recommendation": columnString(statement, 9) ?? "",
                "evidence": parseJSONObject(columnString(statement, 10) ?? "{}") ?? [:],
                "createdAt": columnString(statement, 11) ?? ""
            ]
        }
    }

    func recordSample(
        id: String,
        appBundleIdentifier: String?,
        windowTitle: String?,
        screenshotPath: String?,
        captureJSONPath: String?,
        codexTextPath: String?,
        anchors: [String],
        anchorRecords: [AnchorInput],
        notes: String?
    ) throws {
        let timestamp = now()
        try run("""
        INSERT INTO capture_samples (
            id, app_bundle_id, window_title, screenshot_path, capture_json_path,
            codex_text_path, captured_at, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            app_bundle_id = excluded.app_bundle_id,
            window_title = excluded.window_title,
            screenshot_path = excluded.screenshot_path,
            capture_json_path = excluded.capture_json_path,
            codex_text_path = excluded.codex_text_path,
            notes = excluded.notes
        """, [
            id,
            appBundleIdentifier,
            windowTitle,
            screenshotPath,
            captureJSONPath,
            codexTextPath,
            timestamp,
            notes
        ])
        // Merge plain anchors (source='expected') with typed anchorRecords.
        var records = anchorRecords
        let typedRegexes = Set(records.map { $0.regex })
        for anchor in anchors where !typedRegexes.contains(anchor) {
            records.append(AnchorInput(regex: anchor, source: "expected", required: true, weight: 1.0))
        }
        if !records.isEmpty {
            try run("DELETE FROM sample_anchors WHERE sample_id = ?", [id])
            for record in records where !record.regex.isEmpty {
                try run(
                    "INSERT INTO sample_anchors (sample_id, anchor_regex, source, required, weight) VALUES (?, ?, ?, ?, ?)",
                    [id, record.regex, record.source, record.required ? 1 : 0, record.weight]
                )
            }
        }
    }

    func evaluate(
        sampleID: String,
        ruleID: String?,
        corpus: String,
        outputTextPath: String?,
        rule: JSONObject?,
        metricWeights: JSONObject?
    ) throws -> JSONObject {
        guard let sample = try sample(id: sampleID) else {
            throw AppShotRuleStoreError.missingSample(sampleID)
        }
        let normalizedCorpus = normalizeCorpus(corpus)
        let anchors = try sampleAnchorRecords(sampleID: sampleID)

        // The student output to score: explicit --output-text, else apply the given rule
        // (or stored rule) to the capture, else fall back to the recorded corpus evidence.
        var outputText: String
        var outputSource: String
        if let outputTextPath, let pathNonEmpty = outputTextPath.nonEmpty {
            outputText = try readText(pathNonEmpty)
            outputSource = "outputText"
        } else if let resolvedRule = try resolveRule(rule: rule, ruleID: ruleID),
                  let capturePath = (sample["captureJSONPath"] as? String)?.nonEmpty,
                  let capture = parseJSONObject(try readText(capturePath)) {
            outputText = (applyRuleToCapture(rule: resolvedRule, capture: capture)["text"] as? String) ?? ""
            outputSource = "appliedRule"
        } else {
            outputText = try sampleCorpus(sample, corpus: normalizedCorpus)
            outputSource = "corpus:\(normalizedCorpus)"
        }

        // Baseline = codex.text the un-tuned capture produced (improvement reference).
        let baselineText = (try? sampleCorpus(sample, corpus: "codex")) ?? ""
        let metric = evaluateRuleOutput(
            outputText: outputText,
            baselineText: baselineText,
            anchors: anchors,
            metricWeights: metricWeights
        )

        let timestamp = now()
        let evaluatedRuleID = ruleID ?? (rule?["id"] as? String)
        let score = (metric["score"] as? Double) ?? 0
        let recall = (metric["accessibilityRecall"] as? Double) ?? 0
        let matchedCount = (metric["matchedAnchors"] as? [String])?.count ?? 0
        let missing = (metric["missingAnchors"] as? [String]) ?? []
        let metricJSON = try jsonString(metric)
        try addColumnIfMissing(table: "rule_evaluations", column: "metric_json", definition: "TEXT")
        try run("""
        INSERT INTO rule_evaluations (
            rule_id, sample_id, corpus, score, anchor_recall, matched_anchors,
            total_anchors, missing_anchors_json, metric_json, evaluated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            evaluatedRuleID,
            sampleID,
            normalizedCorpus,
            score,
            recall,
            matchedCount,
            anchors.count,
            try jsonString(missing),
            metricJSON,
            timestamp
        ])

        var payload: JSONObject = metric
        payload["databasePath"] = path
        payload["sampleID"] = sampleID
        payload["ruleID"] = evaluatedRuleID ?? NSNull()
        payload["corpus"] = normalizedCorpus
        payload["outputSource"] = outputSource
        payload["evaluatedAt"] = timestamp
        return payload
    }

    private func resolveRule(rule: JSONObject?, ruleID: String?) throws -> JSONObject? {
        if let rule { return rule }
        guard let ruleID, !ruleID.isEmpty else { return nil }
        return try ruleJSON(id: ruleID)
    }

    func sampleRow(id: String) throws -> JSONObject? {
        try sample(id: id)
    }

    private func sample(id: String) throws -> JSONObject? {
        let rows: [JSONObject] = try query("""
        SELECT id, app_bundle_id, window_title, screenshot_path, capture_json_path, codex_text_path, notes
        FROM capture_samples WHERE id = ?
        """, [id]) { statement in
            var row: JSONObject = [:]
            row["id"] = columnString(statement, 0) ?? ""
            row["appBundleId"] = columnString(statement, 1) ?? NSNull()
            row["windowTitle"] = columnString(statement, 2) ?? NSNull()
            row["screenshotPath"] = columnString(statement, 3) ?? NSNull()
            row["captureJSONPath"] = columnString(statement, 4) ?? NSNull()
            row["codexTextPath"] = columnString(statement, 5) ?? NSNull()
            row["notes"] = columnString(statement, 6) ?? NSNull()
            return row
        }
        return rows.first
    }

    private func sampleAnchors(sampleID: String) throws -> [String] {
        try query("SELECT anchor_regex FROM sample_anchors WHERE sample_id = ? ORDER BY id ASC", [sampleID]) { statement in
            columnString(statement, 0) ?? ""
        }.filter { !$0.isEmpty }
    }

    private func sampleAnchorRecords(sampleID: String) throws -> [AnchorRecord] {
        try query(
            "SELECT anchor_regex, source, weight FROM sample_anchors WHERE sample_id = ? ORDER BY id ASC",
            [sampleID]
        ) { statement in
            let regex = columnString(statement, 0) ?? ""
            let source = columnString(statement, 1) ?? "expected"
            let weight = sqlite3_column_double(statement, 2)
            return AnchorRecord(regex: regex, source: source, weight: weight)
        }.filter { !$0.regex.isEmpty }
    }

    private func sampleCorpus(_ sample: JSONObject, corpus: String) throws -> String {
        var chunks: [String] = []
        let keys: [String]
        switch corpus {
        case "capture":
            keys = ["captureJSONPath"]
        case "combined":
            keys = ["codexTextPath", "captureJSONPath"]
        default:
            keys = ["codexTextPath"]
        }
        for key in keys {
            guard let path = sample[key] as? String, !path.isEmpty else {
                continue
            }
            chunks.append(try readText(path))
        }
        return chunks.joined(separator: "\n")
    }

    private func addColumnIfMissing(table: String, column: String, definition: String) throws {
        let rows: [String] = try query("PRAGMA table_info(\(table))", []) { statement in
            columnString(statement, 1) ?? ""
        }
        guard !rows.contains(column) else {
            return
        }
        try exec("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    private func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw AppShotRuleStoreError.sqlite(message)
        }
    }

    private func run(_ sql: String, _ params: [Any?]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw AppShotRuleStoreError.sqlite(errorMessage())
        }
        defer {
            sqlite3_finalize(statement)
        }
        try bind(params, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppShotRuleStoreError.sqlite(errorMessage())
        }
    }

    private func scalarInt(_ sql: String, _ params: [Any?]) throws -> Int? {
        try query(sql, params) { statement in
            Int(sqlite3_column_int(statement, 0))
        }.first
    }

    private func query<T>(_ sql: String, _ params: [Any?], map: (OpaquePointer?) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw AppShotRuleStoreError.sqlite(errorMessage())
        }
        defer {
            sqlite3_finalize(statement)
        }
        try bind(params, to: statement)
        var rows: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(try map(statement))
            } else if result == SQLITE_DONE {
                break
            } else {
                throw AppShotRuleStoreError.sqlite(errorMessage())
            }
        }
        return rows
    }

    private func bind(_ params: [Any?], to statement: OpaquePointer?) throws {
        for (index, value) in params.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case nil, is NSNull:
                result = sqlite3_bind_null(statement, position)
            case let value as String:
                result = sqlite3_bind_text(statement, position, value, -1, sqliteTransient)
            case let value as Int:
                result = sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Int32:
                result = sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Bool:
                result = sqlite3_bind_int(statement, position, value ? 1 : 0)
            case let value as Double:
                result = sqlite3_bind_double(statement, position, value)
            default:
                result = sqlite3_bind_text(statement, position, String(describing: value!), -1, sqliteTransient)
            }
            guard result == SQLITE_OK else {
                throw AppShotRuleStoreError.sqlite(errorMessage())
            }
        }
    }

    private func errorMessage() -> String {
        sqlite3_errmsg(db).map { String(cString: $0) } ?? "unknown"
    }
}

private func columnString(_ statement: OpaquePointer?, _ column: Int32) -> String? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL,
          let text = sqlite3_column_text(statement, column) else {
        return nil
    }
    return String(cString: text)
}

private func now() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func requiredString(_ value: Any?, field: String) throws -> String {
    guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !string.isEmpty else {
        throw AppShotRuleStoreError.invalidRule("missing string \(field)")
    }
    return string
}

private func firstString(_ value: Any?) -> String? {
    if let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
        return string
    }
    if let array = value as? [Any] {
        return array.compactMap(firstString).first
    }
    return nil
}

private func boolValue(_ value: Any?, defaultValue: Bool) -> Bool {
    if let bool = value as? Bool {
        return bool
    }
    if let number = value as? NSNumber {
        return number.boolValue
    }
    return defaultValue
}

private func intValue(_ value: Any?, defaultValue: Int) -> Int {
    if let int = value as? Int {
        return int
    }
    if let number = value as? NSNumber {
        return number.intValue
    }
    return defaultValue
}

private func doubleValue(_ value: Any?, defaultValue: Double) -> Double {
    if let double = value as? Double {
        return double
    }
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    return defaultValue
}

private func jsonString(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    guard let text = String(data: data, encoding: .utf8) else {
        throw AppShotRuleStoreError.invalidJSON("failed to encode JSON")
    }
    return text
}

private func parseJSONObject(_ text: String) -> JSONObject? {
    guard let data = text.data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: data) as? JSONObject else {
        return nil
    }
    return value
}

private func jsonNullable(_ value: String?) -> Any {
    guard let value, !value.isEmpty else {
        return NSNull()
    }
    return value
}

private func deepMerged(_ base: JSONObject, _ patch: JSONObject) -> JSONObject {
    var output = base
    for (key, value) in patch {
        if let baseObject = output[key] as? JSONObject,
           let patchObject = value as? JSONObject {
            output[key] = deepMerged(baseObject, patchObject)
        } else {
            output[key] = value
        }
    }
    return output
}

private func readText(_ path: String) throws -> String {
    let expanded = (path as NSString).expandingTildeInPath
    guard let text = try? String(contentsOfFile: expanded, encoding: .utf8) else {
        throw AppShotRuleStoreError.readFailed(expanded)
    }
    return text
}

private func normalizeCorpus(_ corpus: String) -> String {
    switch corpus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "capture", "json":
        return "capture"
    case "combined", "all":
        return "combined"
    default:
        return "codex"
    }
}

private func regexContains(_ pattern: String, in text: String) -> Bool {
    if pattern.isEmpty {
        return true
    }
    if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
    return text.localizedCaseInsensitiveContains(pattern)
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Rule application (raw capture -> Accessibility student output + TOON)

private struct RuleLine {
    let source: String
    let text: String
    let importance: Double
}

private struct WeightedRegex {
    let regex: NSRegularExpression
    let weight: Double
}

private func normalizeLine(_ line: String) -> String {
    let collapsed = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func usefulLine(_ line: String) -> Bool {
    guard line.count >= 4 else { return false }
    return line.range(of: "[A-Za-z0-9\\u4e00-\\u9fff]", options: .regularExpression) != nil
}

private func truncateRuleLine(_ line: String, maxLineChars: Int) -> String {
    guard maxLineChars > 0, line.count > maxLineChars else {
        return line
    }
    guard maxLineChars > 3 else {
        return String(line.prefix(maxLineChars))
    }
    return String(line.prefix(maxLineChars - 3)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
}

/// Map normalized OCR text -> visual weight from box height * confidence.
/// Taller, higher-confidence on-screen text is more likely load-bearing.
private func ocrVisualWeights(_ capture: JSONObject) -> [String: Double] {
    var weights: [String: Double] = [:]
    let ocr = capture["ocr"] as? JSONObject ?? [:]
    for case let obs as JSONObject in (ocr["observations"] as? [Any] ?? []) {
        let text = normalizeLine((obs["text"] as? String) ?? "")
        guard !text.isEmpty else { continue }
        let box = obs["boundingBox"] as? JSONObject ?? [:]
        let height = (box["height"] as? Double) ?? 0
        let confidence = (obs["confidence"] as? Double) ?? 0
        let weight = 1.0 + (height * 40.0) + (confidence * 0.5)
        let key = text.lowercased()
        weights[key] = max(weights[key] ?? 0, weight)
    }
    return weights
}

private func visualImportance(_ line: String, source: String, ocrWeight: Double?) -> Double {
    var score = 1.0
    if let ocrWeight, ocrWeight > 0 {
        score += ocrWeight
    } else if source == "ocr" {
        score += 1.5
    }
    if source == "visible" || source == "document" {
        score += 0.8
    }
    score += min(Double(line.count), 160) / 80.0
    if line.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil {
        score += 0.4
    }
    if line.range(of: "^[\\W_]+$", options: .regularExpression) != nil {
        score -= 0.6
    }
    return (score * 10000).rounded() / 10000
}

/// AX text sources from a capture. OCR is intentionally NOT a student source; it is only
/// read for teacher anchor weighting elsewhere.
private func captureTextSources(_ capture: JSONObject) -> [String: String] {
    let ax = capture["accessibility"] as? JSONObject ?? [:]
    var document = ""
    if let docs = ax["documentReferences"] as? [Any] {
        document = docs.compactMap { ($0 as? JSONObject)?["textPreview"] as? String }.joined(separator: "\n")
    }
    return [
        "visible": (ax["visibleText"] as? String) ?? "",
        "accessibility": (ax["text"] as? String) ?? "",
        "document": document
    ]
}

private func compiledRegexes(_ patterns: [Any]?) -> [NSRegularExpression] {
    (patterns ?? []).compactMap { value in
        guard let pattern = value as? String, !pattern.isEmpty else { return nil }
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            return regex
        }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        return try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive])
    }
}

private func weightedRegexes(_ values: [Any]?) -> [WeightedRegex] {
    (values ?? []).compactMap { value in
        let pattern: String
        let weight: Double
        if let string = value as? String {
            pattern = string
            weight = 1.0
        } else if let object = value as? JSONObject,
                  let regex = object["regex"] as? String {
            pattern = regex
            weight = doubleValue(object["weight"], defaultValue: 1.0)
        } else {
            return nil
        }
        guard !pattern.isEmpty else { return nil }
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            return WeightedRegex(regex: regex, weight: weight)
        }
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        guard let regex = try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive]) else {
            return nil
        }
        return WeightedRegex(regex: regex, weight: weight)
    }
}

private func regexMatches(_ regex: NSRegularExpression, _ text: String) -> Bool {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.firstMatch(in: text, range: range) != nil
}

private func regexWeight(_ rules: [WeightedRegex], _ text: String) -> Double {
    rules.reduce(0.0) { total, rule in
        regexMatches(rule.regex, text) ? total + rule.weight : total
    }
}

func applyRuleToCapture(rule: JSONObject, capture: JSONObject) -> JSONObject {
    let action = rule["action"] as? JSONObject ?? [:]
    let keepers = compiledRegexes(action["keepRegex"] as? [Any])
    let droppers = compiledRegexes(action["dropRegex"] as? [Any])
    let boosters = weightedRegexes(action["importanceBoostRegex"] as? [Any])
    let penalties = weightedRegexes(action["importancePenaltyRegex"] as? [Any])
    // OCR is a teacher, never a student source. Strip it no matter what the rule asks.
    let requested = (action["sources"] as? [Any])?.compactMap { $0 as? String } ?? ["visible", "accessibility"]
    let wantedSources = requested.filter { $0 != "ocr" }
    let transport = action["transport"] as? JSONObject ?? [:]
    let maxImportant = (transport["maxImportantLines"] as? Int) ?? 180
    let maxRich = (transport["maxRichLines"] as? Int) ?? 220
    let maxLineChars = (transport["maxLineChars"] as? Int) ?? 0
    let ocrWeights = ocrVisualWeights(capture)
    let sources = captureTextSources(capture)

    var lines: [RuleLine] = []
    var seen = Set<String>()
    for sourceName in wantedSources {
        let body = sources[sourceName] ?? ""
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = normalizeLine(String(raw))
            if !usefulLine(line) { continue }
            if droppers.contains(where: { regexMatches($0, line) }) { continue }
            if !keepers.isEmpty && !keepers.contains(where: { regexMatches($0, line) }) { continue }
            let sourceKey = line.lowercased()
            let outputLine = truncateRuleLine(line, maxLineChars: maxLineChars)
            let key = outputLine.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            var importance = visualImportance(line, source: sourceName, ocrWeight: ocrWeights[sourceKey])
            importance += regexWeight(boosters, line)
            importance -= regexWeight(penalties, line)
            lines.append(RuleLine(source: sourceName, text: outputLine, importance: (importance * 10000).rounded() / 10000))
        }
    }

    let ranked = lines.sorted { $0.importance > $1.importance }
    let important = Array(ranked.prefix(maxImportant))
    let importantKeys = Set(important.map { $0.text })
    let rich = Array(lines.filter { !importantKeys.contains($0.text) }.prefix(maxRich))
    let selected = important + rich
    let text = selected.map { $0.text }.joined(separator: "\n")
    let preserveRaw = (transport["preserveRaw"] as? Bool) ?? true

    let transportText = toonRuleOutput(
        ruleID: (rule["id"] as? String) ?? "",
        strategy: (rule["strategy"] as? String) ?? "",
        bucketID: (rule["bucket"] as? String) ?? "",
        important: important,
        rich: rich,
        totalLineCount: lines.count,
        rawPreserved: preserveRaw
    )

    func encode(_ items: [RuleLine]) -> [JSONObject] {
        items.map { ["source": $0.source, "text": $0.text, "importance": $0.importance] }
    }

    return [
        "text": text,
        "transportFormat": "toon",
        "transportText": transportText,
        "lineCount": selected.count,
        "fullLineCount": lines.count,
        "selectedLineCount": selected.count,
        "transportLineCount": transportText.split(separator: "\n", omittingEmptySubsequences: false).count,
        "sources": Array(Set(lines.map { $0.source })).sorted(),
        "importantLines": encode(important),
        "richLines": encode(rich)
    ]
}

// MARK: - TOON transport

private func toonEscape(_ value: Any?) -> String {
    var text: String
    switch value {
    case let s as String: text = s
    case let d as Double: text = (d == d.rounded()) ? String(Int(d)) : String(d)
    case let i as Int: text = String(i)
    case nil, is NSNull: text = ""
    default: text = "\(value!)"
    }
    text = text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "")
    let needsQuote = text.contains(where: { ",:{}[]\"".contains($0) }) || text != text.trimmingCharacters(in: .whitespaces)
    if needsQuote {
        text = "\"" + text.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    return text
}

private func toonRows(_ fields: [String], _ rows: [RuleLine]) -> [String] {
    var out = ["lines[\(rows.count)]{\(fields.joined(separator: ","))}:"]
    for row in rows {
        let values: [Any?] = fields.map { field in
            switch field {
            case "source": return row.source
            case "importance": return row.importance
            case "text": return row.text
            default: return nil
            }
        }
        out.append("  " + values.map { toonEscape($0) }.joined(separator: ","))
    }
    return out
}

private func toonRuleOutput(
    ruleID: String,
    strategy: String,
    bucketID: String,
    important: [RuleLine],
    rich: [RuleLine],
    totalLineCount: Int,
    rawPreserved: Bool
) -> String {
    var lines = [
        "ruleOutput:",
        "  ruleID: \(toonEscape(ruleID))",
        "  strategy: \(toonEscape(strategy))",
        "  bucketID: \(toonEscape(bucketID))",
        "  totalLineCount: \(totalLineCount)",
        "  rawPreserved: \(rawPreserved ? "true" : "false")"
    ]
    if !important.isEmpty {
        lines.append("important:")
        lines.append(contentsOf: toonRows(["source", "importance", "text"], important).map { "  " + $0 })
    }
    if !rich.isEmpty {
        lines.append("rich:")
        lines.append(contentsOf: toonRows(["source", "importance", "text"], rich).map { "  " + $0 })
    }
    return lines.joined(separator: "\n")
}

// MARK: - Dual metric (accessibility recall + information density)

struct AnchorRecord {
    let regex: String
    let source: String
    let weight: Double
}

public struct AnchorInput {
    public let regex: String
    public let source: String
    public let required: Bool
    public let weight: Double
    public init(regex: String, source: String = "expected", required: Bool = true, weight: Double = 1.0) {
        self.regex = regex
        self.source = source
        self.required = required
        self.weight = weight
    }
}

/// Score an AX (student) output against the on-screen teacher truth set.
/// Core objective = accessibilityRecall, kept honest by information density so a
/// whole-tree dump (high recall, low density) cannot win.
/// OCR anchors are teacher-only: they remain in teacherRecall/axGap but are excluded
/// from student accessibilityRecall because rules must not emit OCR output.
func evaluateRuleOutput(
    outputText: String,
    baselineText: String,
    anchors: [AnchorRecord],
    metricWeights: JSONObject?
) -> JSONObject {
    let total = anchors.count
    let hit = anchors.map { regexContains($0.regex, in: outputText) }
    let baseHit = anchors.map { regexContains($0.regex, in: baselineText) }

    let weightedTotal = max(anchors.reduce(0.0) { $0 + $1.weight }, 1.0)
    let studentAnchors = anchors.filter { $0.source.lowercased() != "ocr" }
    let studentTotal = studentAnchors.count
    let studentWeightedTotal = max(studentAnchors.reduce(0.0) { $0 + $1.weight }, 1.0)
    var weightedMatched = 0.0
    var weightedBaseline = 0.0
    var weightedTeacherMatched = 0.0
    var weightedTeacherBaseline = 0.0
    var matched: [String] = []
    var missing: [String] = []
    var baseline: [String] = []
    var teacherMatched: [String] = []
    var teacherMissing: [String] = []
    var teacherBaseline: [String] = []
    var axGap: [String] = []
    var ocrTotal = 0
    var ocrMatched = 0
    var matchedPayload = 0.0

    for (index, anchor) in anchors.enumerated() {
        let isOCR = anchor.source.lowercased() == "ocr"
        if isOCR { ocrTotal += 1 }
        if hit[index] {
            teacherMatched.append(anchor.regex)
            weightedTeacherMatched += anchor.weight
            if !isOCR {
                matched.append(anchor.regex)
                weightedMatched += anchor.weight
            }
            matchedPayload += Double(unescapedLength(anchor.regex)) * anchor.weight
            if isOCR { ocrMatched += 1 }
        } else {
            teacherMissing.append(anchor.regex)
            if !isOCR {
                missing.append(anchor.regex)
            }
            if isOCR { axGap.append(anchor.regex) }
        }
        if baseHit[index] {
            teacherBaseline.append(anchor.regex)
            weightedTeacherBaseline += anchor.weight
            if !isOCR {
                baseline.append(anchor.regex)
                weightedBaseline += anchor.weight
            }
        }
    }

    let recall = studentTotal == 0 ? 1.0 : Double(matched.count) / Double(studentTotal)
    let baselineRecall = studentTotal == 0 ? 1.0 : Double(baseline.count) / Double(studentTotal)
    let teacherRecall = total == 0 ? 1.0 : Double(teacherMatched.count) / Double(total)
    let teacherBaselineRecall = total == 0 ? 1.0 : Double(teacherBaseline.count) / Double(total)
    let weightedRecall = weightedMatched / studentWeightedTotal
    let weightedBaselineRecall = weightedBaseline / studentWeightedTotal
    let weightedTeacherRecall = weightedTeacherMatched / weightedTotal
    let weightedTeacherBaselineRecall = weightedTeacherBaseline / weightedTotal
    let accessibilityRecall = recall
    let charCount = outputText.count
    let anchorPayloadRatio = charCount == 0 ? 0.0 : min(1.0, matchedPayload / Double(charCount))
    let outputLines = outputText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let uniqueLineRatio = outputLines.isEmpty ? 1.0 : Double(Set(outputLines.map { $0.lowercased() }).count) / Double(outputLines.count)
    let entropy = charEntropy(outputText)
    let informationDensity = max(0.0, min(1.0, min(1.0, anchorPayloadRatio * 2.0) * min(1.0, max(entropy, 0.1) / 4.0) * max(0.25, uniqueLineRatio)))
    let ocrOracleRecall = ocrTotal == 0 ? 1.0 : Double(ocrMatched) / Double(ocrTotal)
    let lineCount = outputLines.count

    let mw = metricWeights ?? [:]
    let wRecall = (mw["weightedVisualRecall"] as? Double) ?? 0.55
    let wAnchor = (mw["anchorRecall"] as? Double) ?? 0.25
    let wDensity = (mw["informationDensity"] as? Double) ?? 0.20
    let denom = (wRecall + wAnchor + wDensity) == 0 ? 1.0 : (wRecall + wAnchor + wDensity)
    let recallDenom = (wRecall + wAnchor) == 0 ? 1.0 : (wRecall + wAnchor)
    let recallComponent = (weightedRecall * wRecall + accessibilityRecall * wAnchor) / recallDenom
    let weightedObjective = (weightedRecall * wRecall + accessibilityRecall * wAnchor + informationDensity * wDensity) / denom
    let densityComponent = informationDensity
    var score = 0.0
    if recallComponent + densityComponent > 0 {
        let beta2 = 4.0
        let blended = (1 + beta2) * recallComponent * densityComponent / (beta2 * densityComponent + recallComponent)
        score = max(0.0, min(1.0, 0.5 * weightedObjective + 0.5 * blended))
    }

    return [
        "score": score,
        "anchorRecall": recall,
        "accessibilityRecall": accessibilityRecall,
        "teacherRecall": teacherRecall,
        "baselineRecall": baselineRecall,
        "teacherBaselineRecall": teacherBaselineRecall,
        "weightedVisualRecall": weightedRecall,
        "weightedBaselineRecall": weightedBaselineRecall,
        "weightedTeacherRecall": weightedTeacherRecall,
        "weightedTeacherBaselineRecall": weightedTeacherBaselineRecall,
        "density": anchorPayloadRatio,
        "informationDensity": informationDensity,
        "uniqueLineRatio": uniqueLineRatio,
        "charEntropy": entropy,
        "ocrOracleRecall": ocrOracleRecall,
        "axGap": axGap,
        "axGapCount": axGap.count,
        "improvement": recall - baselineRecall,
        "matchedAnchors": matched,
        "missingAnchors": missing,
        "teacherMatchedAnchors": teacherMatched,
        "teacherMissingAnchors": teacherMissing,
        "totalAnchors": total,
        "studentAnchorTotal": studentTotal,
        "ocrAnchorTotal": ocrTotal,
        "lineCount": lineCount,
        "charCount": charCount
    ]
}

private func unescapedLength(_ pattern: String) -> Int {
    pattern.replacingOccurrences(of: "\\", with: "").count
}

private func charEntropy(_ text: String) -> Double {
    guard !text.isEmpty else { return 0.0 }
    var counts: [Character: Int] = [:]
    for character in text {
        counts[character, default: 0] += 1
    }
    let total = Double(text.count)
    return counts.values.reduce(0.0) { partial, count in
        let probability = Double(count) / total
        return partial - probability * log2(probability)
    }
}
