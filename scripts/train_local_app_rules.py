#!/usr/bin/env python3
import argparse
import json
import pathlib
import re
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from math import log2


DEFAULT_CATALOG_PATH = pathlib.Path(__file__).resolve().parent.parent / "rules" / "seed" / "local-app-strategies.json"

# Runtime state loaded from the JSON catalog. This script is intentionally a
# rule interpreter/trainer; app strategies, capture profiles, output templates,
# and rollout defaults live in JSON.
FOCUS_BUNDLES = set()
SENSITIVE_BUNDLES = set()
SENSITIVE_TITLE_RE = re.compile(r"(?!)")
BUCKETS = []
GENERIC_TREE_REGEX = ""
GENERIC_CAPTURE_PROFILES = []
GENERIC_VARIANTS = []
RULE_TEMPLATE = {}
CAPTURE_PROFILES = {}
TRAINING_DEFAULTS = {}
IMPROVEMENT_RECOMMENDATIONS = {}


def load_catalog(path):
    catalog_path = pathlib.Path(path).expanduser()
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    if not isinstance(catalog.get("ruleTemplate"), dict):
        raise ValueError("catalog must include ruleTemplate as a JSON object")
    if not isinstance((catalog.get("trainingDefaults") or {}).get("captureArgs"), list):
        raise ValueError("catalog must include trainingDefaults.captureArgs as a JSON array")
    if "anchorSourceCaps" in (catalog.get("trainingDefaults") or {}) and not isinstance(catalog["trainingDefaults"]["anchorSourceCaps"], dict):
        raise ValueError("trainingDefaults.anchorSourceCaps must be a JSON object when present")

    global FOCUS_BUNDLES, SENSITIVE_BUNDLES, SENSITIVE_TITLE_RE
    global BUCKETS, GENERIC_TREE_REGEX, GENERIC_CAPTURE_PROFILES, GENERIC_VARIANTS
    global RULE_TEMPLATE, CAPTURE_PROFILES, TRAINING_DEFAULTS, IMPROVEMENT_RECOMMENDATIONS

    FOCUS_BUNDLES = set(catalog.get("focusBundles") or [])
    SENSITIVE_BUNDLES = set(catalog.get("sensitiveBundles") or [])
    SENSITIVE_TITLE_RE = re.compile(catalog.get("sensitiveTitleRegex") or r"(?!)", re.I)
    BUCKETS = catalog.get("buckets") or []
    generic = catalog.get("generic") or {}
    GENERIC_TREE_REGEX = generic.get("treeRegex") or ""
    GENERIC_CAPTURE_PROFILES = generic.get("captureProfiles") or []
    GENERIC_VARIANTS = generic.get("variants") or []
    RULE_TEMPLATE = catalog["ruleTemplate"]
    CAPTURE_PROFILES = catalog.get("captureProfiles") or {}
    TRAINING_DEFAULTS = catalog.get("trainingDefaults") or {}
    IMPROVEMENT_RECOMMENDATIONS = catalog.get("improvementRecommendations") or {}
    return catalog


def run(command, timeout=None):
    return subprocess.run(command, check=True, text=True, capture_output=True, timeout=timeout)


def run_json(command, timeout=None):
    return json.loads(run(command, timeout=timeout).stdout)


def stamp():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def iso_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def slug(text, limit=96):
    text = re.sub(r"-+", "-", "".join(ch if ch.isalnum() or ch in "-_." else "-" for ch in str(text))).strip("-")
    return (text or "untitled")[:limit]


def area(window):
    if isinstance(window.get("area"), (int, float)):
        return int(window["area"])
    bounds = window.get("bounds") or {}
    return int((bounds.get("width") or 0) * (bounds.get("height") or 0))


def is_sensitive(bundle_id, title):
    return bundle_id in SENSITIVE_BUNDLES or bool(SENSITIVE_TITLE_RE.search(title or ""))


def bucket_for_bundle(bundle_id, app_name=None):
    for bucket in BUCKETS:
        if bundle_id in (bucket.get("appBundleIDs") or []):
            return bucket
    return generic_bucket(bundle_id, app_name)


def generic_bucket(bundle_id, app_name=None):
    safe_id = slug(bundle_id or app_name or "unknown-app").lower() or "unknown-app"
    base = f"app-{safe_id}"
    variants = []
    for variant in GENERIC_VARIANTS:
        item = dict(variant)
        item.setdefault("id", f"{base}-text")
        variants.append(item)
    return {
        "bucketID": base,
        "name": f"{app_name or bundle_id or 'Unknown app'} (generic)",
        "appBundleIDs": [bundle_id] if bundle_id else [],
        "treeRegex": GENERIC_TREE_REGEX,
        "captureProfiles": GENERIC_CAPTURE_PROFILES,
        "generic": True,
        "variants": variants,
    }


def collect_windows(payload, args):
    selected = []
    seen = set()
    target_bundles = set(args.target_bundle or [])
    all_apps = args.all_visible or args.all_apps
    for app in payload.get("applications", []):
        bundle_id = app.get("bundleIdentifier") or ""
        app_name = app.get("localizedName") or bundle_id
        if target_bundles and bundle_id not in target_bundles:
            continue
        if not target_bundles and not all_apps and bundle_id not in FOCUS_BUNDLES:
            continue
        for source in ("windows", "accessibilityWindows"):
            for window in app.get(source, []) or []:
                title = window.get("title") or ""
                if area(window) < args.min_area:
                    continue
                sensitive = is_sensitive(bundle_id, title)
                if sensitive and args.privacy_mode == "skip-sensitive":
                    continue
                bounds = window.get("bounds") or {}
                geometry = tuple(int(bounds.get(key) or 0) for key in ("x", "y", "width", "height"))
                key = (bundle_id, title, geometry) if title or any(geometry) else (bundle_id, window.get("windowID") or "", source)
                if key in seen:
                    continue
                seen.add(key)
                selected.append({
                    "appName": app_name,
                    "bundleID": bundle_id,
                    "pid": app.get("processIdentifier"),
                    "window": window,
                    "title": title,
                    "source": source,
                    "sensitive": sensitive,
                })
    return selected[: args.max_windows] if args.max_windows else selected


def text_sources(capture):
    ax = capture.get("accessibility") or {}
    ocr = capture.get("ocr") or {}
    docs = ax.get("documentReferences") or []
    return {
        "codex": ((capture.get("codex") or {}).get("text") or ""),
        "visible": ax.get("visibleText") or "",
        "accessibility": ax.get("text") or "",
        "ocr": ocr.get("text") or "",
        "document": "\n".join((doc.get("textPreview") or "") for doc in docs if isinstance(doc, dict)),
    }


def norm_line(line):
    return re.sub(r"\s+", " ", str(line)).strip()


def useful(line):
    return len(line) >= 4 and bool(re.search(r"[A-Za-z0-9\u4e00-\u9fff]", line))


def teacher_sources():
    return TRAINING_DEFAULTS.get("teacherSources") or ["ocr", "visible", "accessibility", "document"]


def anchor_source_order():
    configured = TRAINING_DEFAULTS.get("anchorSourceOrder") or []
    ordered = [source for source in configured if source in teacher_sources()]
    return ordered + [source for source in teacher_sources() if source not in ordered]


def anchor_source_caps():
    return TRAINING_DEFAULTS.get("anchorSourceCaps") or {}


def anchor_rejecters():
    return [compile_regex(pattern) for pattern in TRAINING_DEFAULTS.get("anchorRejectRegex") or []]


def ocr_anchor_allowed(line):
    quality = TRAINING_DEFAULTS.get("ocrAnchorQuality") or {}
    min_length = int(quality.get("minLength") or 0)
    min_content_ratio = float(quality.get("minContentRatio") or 0.0)
    min_letter_or_cjk = int(quality.get("minLetterOrCJKCount") or 0)
    max_single_tokens = int(quality.get("maxSingleCharacterTokens") or 999999)
    if len(line) < min_length:
        return False
    content_count = len(re.findall(r"[A-Za-z0-9\u4e00-\u9fff]", line))
    if len(line) and content_count / len(line) < min_content_ratio:
        return False
    letter_or_cjk_count = len(re.findall(r"[A-Za-z\u4e00-\u9fff]", line))
    if letter_or_cjk_count < min_letter_or_cjk:
        return False
    single_tokens = re.findall(r"(?<![A-Za-z0-9])[A-Za-z0-9](?![A-Za-z0-9])", line)
    if len(single_tokens) > max_single_tokens:
        return False
    return True


def make_anchors(capture, max_anchors):
    sources = text_sources(capture)
    codex_lower = sources["codex"].casefold()
    ocr_weights = ocr_visual_weights(capture)
    rejecters = anchor_rejecters()
    candidates_by_source = {}
    for source_name in teacher_sources():
        for raw in sources.get(source_name, "").splitlines():
            line = norm_line(raw)
            if not useful(line):
                continue
            if any(regex and regex.search(line) for regex in rejecters):
                continue
            if source_name == "ocr" and not ocr_anchor_allowed(line):
                continue
            in_codex = line.casefold() in codex_lower
            score = (80 if not in_codex else 20) + min(len(line), 120) / 10
            if source_name == "ocr":
                score += 8
            if re.search(r"[\u4e00-\u9fff]", line):
                score += 5
            candidates_by_source.setdefault(source_name, []).append((score, source_name, line, in_codex))

    caps = anchor_source_caps()
    candidates = []
    if caps:
        seen_candidate_keys = set()
        for source_name in anchor_source_order():
            source_candidates = sorted(candidates_by_source.get(source_name, []), reverse=True)
            cap = int(caps.get(source_name, max_anchors))
            if cap <= 0:
                continue
            added = 0
            for item in source_candidates:
                key = item[2].casefold()
                if key in seen_candidate_keys:
                    continue
                candidates.append(item)
                seen_candidate_keys.add(key)
                added += 1
                if added >= cap:
                    break
        candidates.sort(reverse=True)
    else:
        candidates = sorted(
            [item for items in candidates_by_source.values() for item in items],
            reverse=True,
        )

    anchors, labels, seen = [], [], set()
    for _, source_name, line, in_codex in candidates:
        key = line.casefold()
        if key in seen:
            continue
        seen.add(key)
        anchors.append(re.escape(line[:220]))
        labels.append({
            "source": source_name,
            "length": len(line),
            "baselineCodexContains": in_codex,
            "visualImportance": visual_importance(line, source_name, ocr_weights.get(key)),
        })
        if len(anchors) >= max_anchors:
            break
    return anchors, labels


def compile_regex(pattern):
    if not pattern:
        return None
    try:
        return re.compile(pattern, re.I)
    except re.error:
        return re.compile(re.escape(pattern), re.I)


def compile_weighted_regexes(items):
    weighted = []
    for item in items or []:
        if isinstance(item, str):
            pattern, weight = item, 1.0
        elif isinstance(item, dict):
            pattern, weight = item.get("regex") or "", float(item.get("weight", 1.0))
        else:
            continue
        regex = compile_regex(pattern)
        if regex:
            weighted.append((regex, weight))
    return weighted


def regex_weight(line, weighted_regexes):
    return sum(weight for regex, weight in weighted_regexes if regex.search(line))


def deep_merge(base, patch):
    if not isinstance(base, dict) or not isinstance(patch, dict):
        return patch
    merged = dict(base)
    for key, value in patch.items():
        merged[key] = deep_merge(merged.get(key), value) if key in merged else value
    return merged


def context_value(context, key_path):
    value = context
    for part in key_path.split("."):
        if isinstance(value, dict) and part in value:
            value = value[part]
            continue
        raise KeyError(f"unknown template placeholder: {key_path}")
    return value


def render_template(value, context):
    if isinstance(value, dict):
        return {key: render_template(item, context) for key, item in value.items()}
    if isinstance(value, list):
        return [render_template(item, context) for item in value]
    if isinstance(value, str):
        exact = re.fullmatch(r"\$\{([A-Za-z0-9_.]+)\}", value)
        if exact:
            return context_value(context, exact.group(1))

        def replace(match):
            return str(context_value(context, match.group(1)))

        return re.sub(r"\$\{([A-Za-z0-9_.]+)\}", replace, value)
    return value


def rule_json(bucket, variant):
    rule = render_template(RULE_TEMPLATE, {
        "bucket": bucket,
        "variant": variant,
    })
    return deep_merge(rule, variant.get("rulePatch") or {})


def upsert_rule(appshot, db_path, rule, rule_dir):
    rule_dir.mkdir(parents=True, exist_ok=True)
    path = rule_dir / f"{rule['id']}-{slug(rule.get('strategy', 'variant'))}.json"
    path.write_text(json.dumps(rule, ensure_ascii=False, indent=2), encoding="utf-8")
    payload = run_json([appshot, "rules", "upsert", "--db", str(db_path), "--rule-json-file", str(path)])
    payload["ruleID"] = rule["id"]
    payload["strategy"] = rule.get("strategy")
    payload["ruleJSONPath"] = str(path)
    payload["outputKind"] = "upsertable-json-rule"
    return payload


def ensure_bucket(conn, bucket, selected=None):
    now = iso_now()
    primary_bundle_id = (bucket.get("appBundleIDs") or [""])[0]
    conn.execute(
        """
        INSERT INTO rule_strategy_buckets (
            bucket_id, app_bundle_id, name, description, selected_rule_id,
            selected_rule_version, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(bucket_id) DO UPDATE SET
            name = excluded.name,
            description = excluded.description,
            selected_rule_id = COALESCE(excluded.selected_rule_id, selected_rule_id),
            selected_rule_version = COALESCE(excluded.selected_rule_version, selected_rule_version),
            updated_at = excluded.updated_at
        """,
        (
            bucket["bucketID"],
            primary_bundle_id,
            bucket.get("name") or bucket["bucketID"],
            "App-specific rule strategy bucket generated by local training.",
            selected[0] if selected else None,
            selected[1] if selected else None,
            now,
            now,
        ),
    )
    for bundle_id in bucket.get("appBundleIDs") or []:
        conn.execute(
            """
            INSERT OR IGNORE INTO rule_strategy_bucket_apps (bucket_id, app_bundle_id, created_at)
            VALUES (?, ?, ?)
            """,
            (bucket["bucketID"], bundle_id, now),
        )
    conn.commit()


def fetch_rule_versions(conn, rule_ids, max_versions):
    if not rule_ids:
        return []
    placeholders = ",".join("?" for _ in rule_ids)
    rows = conn.execute(
        f"""
        SELECT rule_id, version, rule_json
        FROM rule_versions
        WHERE rule_id IN ({placeholders})
        ORDER BY rule_id, version DESC
        """,
        list(rule_ids),
    ).fetchall()
    grouped = {}
    for rule_id, version, rule_text in rows:
        grouped.setdefault(rule_id, [])
        if len(grouped[rule_id]) < max_versions:
            grouped[rule_id].append((version, json.loads(rule_text)))
    return [(rule_id, version, rule) for rule_id, versions in grouped.items() for version, rule in versions]


def ocr_visual_weights(capture):
    weights = {}
    ocr = capture.get("ocr") or {}
    for obs in ocr.get("observations") or []:
        if not isinstance(obs, dict):
            continue
        text = norm_line(obs.get("text") or "")
        if not text:
            continue
        box = obs.get("boundingBox") or {}
        height = float(box.get("height") or 0.0)
        confidence = float(obs.get("confidence") or 0.0)
        weight = 1.0 + (height * 40.0) + (confidence * 0.5)
        key = text.casefold()
        weights[key] = max(weights.get(key, 0.0), weight)
    return weights


def visual_importance(line, source_name, ocr_weight=None):
    score = 1.0
    if ocr_weight:
        score += ocr_weight
    elif source_name == "ocr":
        score += 1.5
    if source_name in ("visible", "document"):
        score += 0.8
    score += min(len(line), 160) / 80.0
    if re.search(r"[\u4e00-\u9fff]", line):
        score += 0.4
    if re.match(r"^[\W_]+$", line):
        score -= 0.6
    return round(score, 4)


def toon_escape(value):
    text = "" if value is None else str(value)
    text = text.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "")
    if any(ch in text for ch in (",", ":", "{", "}", "[", "]", '"')) or text != text.strip():
        text = '"' + text.replace('"', '\\"') + '"'
    return text


def toon_rows(header, rows):
    fields = list(header)
    out = [f"lines[{len(rows)}]{{{','.join(fields)}}}:"]
    for row in rows:
        out.append("  " + ",".join(toon_escape(row.get(field)) for field in fields))
    return out


def toon_rule_output(payload):
    lines = [
        "ruleOutput:",
        f"  ruleID: {toon_escape(payload.get('ruleID'))}",
        f"  strategy: {toon_escape(payload.get('strategy'))}",
        f"  bucketID: {toon_escape(payload.get('bucketID'))}",
        f"  totalLineCount: {int(payload.get('totalLineCount') or 0)}",
        f"  rawPreserved: {'true' if payload.get('rawPreserved') else 'false'}",
    ]
    important = payload.get("importantLines") or []
    rich = payload.get("richLines") or []
    if important:
        lines.append("important:")
        lines.extend("  " + row for row in toon_rows(["source", "importance", "text"], important))
    if rich:
        lines.append("rich:")
        lines.extend("  " + row for row in toon_rows(["source", "importance", "text"], rich))
    return "\n".join(lines)


def apply_rule(capture, rule):
    action = rule.get("action") or {}
    wanted_sources = list(action.get("sources") or [])
    if not wanted_sources:
        raise ValueError(f"rule {rule.get('id')} must define action.sources")
    if action.get("ocrPolicy") == "teacher-only":
        wanted_sources = [source for source in wanted_sources if source != "ocr"]

    keepers = [compile_regex(x) for x in action.get("keepRegex") or []]
    droppers = [compile_regex(x) for x in action.get("dropRegex") or []]
    boosters = compile_weighted_regexes(action.get("importanceBoostRegex"))
    penalties = compile_weighted_regexes(action.get("importancePenaltyRegex"))
    transport = action.get("transport") or {}
    max_important = int(transport["maxImportantLines"]) if transport.get("maxImportantLines") is not None else 180
    max_rich = int(transport["maxRichLines"]) if transport.get("maxRichLines") is not None else 220

    ocr_weights = ocr_visual_weights(capture)
    sources = text_sources(capture)
    lines, seen = [], set()
    for source_name in wanted_sources:
        for raw in sources.get(source_name, "").splitlines():
            line = norm_line(raw)
            if not useful(line):
                continue
            if any(regex and regex.search(line) for regex in droppers):
                continue
            if keepers and not any(regex and regex.search(line) for regex in keepers):
                continue
            key = line.casefold()
            if key in seen:
                continue
            seen.add(key)
            importance = visual_importance(line, source_name, ocr_weights.get(key))
            importance += regex_weight(line, boosters)
            importance -= regex_weight(line, penalties)
            lines.append({
                "source": source_name,
                "text": line,
                "importance": round(importance, 4),
            })

    ranked = sorted(lines, key=lambda item: item["importance"], reverse=True)
    important_ids = {id(item) for item in ranked[:max_important]}
    important = [item for item in ranked if id(item) in important_ids]
    rich = [item for item in lines if id(item) not in important_ids][:max_rich]
    selected = important + rich
    text = "\n".join(item["text"] for item in selected)
    transport_text = toon_rule_output({
        "ruleID": rule.get("id") or "",
        "strategy": rule.get("strategy") or "",
        "bucketID": rule.get("bucket") or "",
        "importantLines": important,
        "richLines": rich,
        "totalLineCount": len(lines),
        "rawPreserved": bool(transport.get("preserveRaw", True)),
    })
    return {
        "text": text,
        "transportFormat": transport.get("format") or "toon",
        "transportText": transport_text,
        "lineCount": len(selected),
        "fullLineCount": len(lines),
        "selectedLineCount": len(selected),
        "transportLineCount": len(transport_text.splitlines()),
        "sources": sorted({item["source"] for item in selected}),
        "lines": selected,
        "allLines": lines,
        "importantLines": important,
        "richLines": rich,
    }


def regex_contains(pattern, text):
    try:
        return re.search(pattern, text, re.I | re.M) is not None
    except re.error:
        return pattern.casefold() in text.casefold()


def unescaped_length(pattern):
    return len(pattern.replace("\\", ""))


def char_entropy(text):
    if not text:
        return 0.0
    counts = {}
    for char in text:
        counts[char] = counts.get(char, 0) + 1
    total = len(text)
    return sum(-(count / total) * log2(count / total) for count in counts.values())


def evaluate_output(output_text, codex_text, anchors, anchor_labels=None):
    anchor_labels = anchor_labels or []
    weights, sources = [], []
    for index, _ in enumerate(anchors):
        label = anchor_labels[index] if index < len(anchor_labels) else {}
        weights.append(float(label.get("visualImportance") or 1.0))
        sources.append(label.get("source") or "expected")

    hit = [regex_contains(anchor, output_text) for anchor in anchors]
    base_hit = [regex_contains(anchor, codex_text) for anchor in anchors]
    student_mask = [source != "ocr" for source in sources]
    matched = [anchor for anchor, ok, student in zip(anchors, hit, student_mask) if ok and student]
    baseline = [anchor for anchor, ok, student in zip(anchors, base_hit, student_mask) if ok and student]
    teacher_matched = [anchor for anchor, ok in zip(anchors, hit) if ok]
    teacher_baseline = [anchor for anchor, ok in zip(anchors, base_hit) if ok]

    total = len(anchors)
    weighted_total = sum(weights) or 1.0
    student_total = sum(1 for student in student_mask if student)
    student_weighted_total = sum(weight for weight, student in zip(weights, student_mask) if student) or 1.0
    weighted_recall = sum(weight for weight, ok, student in zip(weights, hit, student_mask) if ok and student) / student_weighted_total
    weighted_baseline = sum(weight for weight, ok, student in zip(weights, base_hit, student_mask) if ok and student) / student_weighted_total
    teacher_weighted_recall = sum(weight for weight, ok in zip(weights, hit) if ok) / weighted_total
    teacher_weighted_baseline = sum(weight for weight, ok in zip(weights, base_hit) if ok) / weighted_total
    recall = 1.0 if student_total == 0 else len(matched) / student_total
    baseline_recall = 1.0 if student_total == 0 else len(baseline) / student_total
    teacher_recall = 1.0 if total == 0 else len(teacher_matched) / total
    teacher_baseline_recall = 1.0 if total == 0 else len(teacher_baseline) / total

    ocr_total = sum(1 for source in sources if source == "ocr")
    ocr_matched = sum(1 for source, ok in zip(sources, hit) if source == "ocr" and ok)
    ocr_oracle_recall = 1.0 if ocr_total == 0 else ocr_matched / ocr_total
    ax_gap = [anchor for anchor, source, ok in zip(anchors, sources, hit) if source == "ocr" and not ok]

    char_count = len(output_text)
    matched_payload = sum(
        unescaped_length(anchor) * weight
        for anchor, weight, ok in zip(anchors, weights, hit)
        if ok
    )
    density = 0.0 if char_count == 0 else min(1.0, matched_payload / char_count)
    output_lines = [line.strip() for line in output_text.splitlines() if line.strip()]
    unique_line_ratio = 1.0 if not output_lines else len({line.casefold() for line in output_lines}) / len(output_lines)
    entropy = char_entropy(output_text)
    information_density = max(
        0.0,
        min(
            1.0,
            min(1.0, density * 2.0) *
            min(1.0, max(entropy, 0.1) / 4.0) *
            max(0.25, unique_line_ratio),
        ),
    )

    metric_weights = TRAINING_DEFAULTS.get("metricWeights") or {}
    w_recall = float(metric_weights.get("weightedVisualRecall", 0.55))
    w_anchor = float(metric_weights.get("anchorRecall", 0.25))
    w_density = float(metric_weights.get("informationDensity", 0.20))
    denom = (w_recall + w_anchor + w_density) or 1.0
    recall_denom = (w_recall + w_anchor) or 1.0
    recall_component = (weighted_recall * w_recall + recall * w_anchor) / recall_denom
    weighted_objective = (weighted_recall * w_recall + recall * w_anchor + information_density * w_density) / denom
    if recall_component + information_density <= 0:
        score = 0.0
    else:
        beta2 = 4.0
        blended = (1 + beta2) * recall_component * information_density / (beta2 * information_density + recall_component)
        score = max(0.0, min(1.0, 0.5 * weighted_objective + 0.5 * blended))

    return {
        "score": score,
        "anchorRecall": recall,
        "accessibilityRecall": recall,
        "teacherRecall": teacher_recall,
        "baselineRecall": baseline_recall,
        "teacherBaselineRecall": teacher_baseline_recall,
        "weightedVisualRecall": weighted_recall,
        "weightedBaselineRecall": weighted_baseline,
        "weightedTeacherRecall": teacher_weighted_recall,
        "weightedTeacherBaselineRecall": teacher_weighted_baseline,
        "density": density,
        "informationDensity": information_density,
        "uniqueLineRatio": unique_line_ratio,
        "charEntropy": entropy,
        "ocrOracleRecall": ocr_oracle_recall,
        "axGap": ax_gap,
        "axGapCount": len(ax_gap),
        "improvement": recall - baseline_recall,
        "weightedImprovement": weighted_recall - weighted_baseline,
        "matchedAnchors": matched,
        "missingAnchors": [anchor for anchor, ok, student in zip(anchors, hit, student_mask) if not ok and student],
        "teacherMatchedAnchors": teacher_matched,
        "teacherMissingAnchors": [anchor for anchor, ok in zip(anchors, hit) if not ok],
        "totalAnchors": total,
        "studentAnchorTotal": student_total,
        "ocrAnchorTotal": ocr_total,
        "lineCount": len([line for line in output_text.splitlines() if line.strip()]),
        "charCount": char_count,
    }


def insert_run(conn, sample, bucket, rule_id, version, output, metric, output_path):
    run_id = f"{sample['sampleID']}--{rule_id}-v{version}"
    now = iso_now()
    output_json = json.dumps(output, ensure_ascii=False, sort_keys=True)
    metric_json = json.dumps(metric, ensure_ascii=False, sort_keys=True)
    conn.execute(
        """
        INSERT OR REPLACE INTO rule_run_outputs (
            run_id, sample_id, rule_id, rule_version, bucket_id, app_bundle_id,
            output_path, output_preview, output_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            run_id,
            sample["sampleID"],
            rule_id,
            version,
            bucket["bucketID"],
            sample["bundleID"],
            str(output_path),
            output["text"][:2000],
            output_json,
            now,
        ),
    )
    conn.execute(
        """
        INSERT OR REPLACE INTO rule_run_metrics (
            run_id, sample_id, rule_id, rule_version, bucket_id, score,
            anchor_recall, baseline_recall, improvement, matched_anchors,
            total_anchors, missing_anchors_json, metric_json, evaluated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            run_id,
            sample["sampleID"],
            rule_id,
            version,
            bucket["bucketID"],
            metric["score"],
            metric["anchorRecall"],
            metric["baselineRecall"],
            metric["improvement"],
            len(metric["matchedAnchors"]),
            metric["totalAnchors"],
            json.dumps(metric["missingAnchors"], ensure_ascii=False),
            metric_json,
            now,
        ),
    )

    recall = metric.get("accessibilityRecall", metric["anchorRecall"])
    density = metric.get("density", 1.0)
    density_floor = float(TRAINING_DEFAULTS.get("densityFloor") or 0.02)
    if recall < 1 or density < density_floor:
        reason = "rule_output_missed_value_anchors" if recall < 1 else "rule_output_low_information_density"
        recommendation = IMPROVEMENT_RECOMMENDATIONS.get(
            reason,
            IMPROVEMENT_RECOMMENDATIONS.get("default", "Patch the rule JSON and replay the recorded samples."),
        )
        severity = 2 if recall < 1 and metric.get("axGapCount", 0) > 0 else 1
        conn.execute(
            """
            INSERT INTO rule_improvement_pool (
                sample_id, rule_id, rule_version, bucket_id, app_bundle_id,
                severity, status, reason, recommendation, evidence_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, 'open', ?, ?, ?, ?)
            """,
            (
                sample["sampleID"],
                rule_id,
                version,
                bucket["bucketID"],
                sample["bundleID"],
                severity,
                reason,
                recommendation,
                metric_json,
                now,
            ),
        )
    conn.commit()
    return run_id


def capture_context(args, target, bucket, paths):
    return {
        "args": {
            "electronTimeout": args.electron_timeout,
            "browserDOMTimeout": args.browser_dom_timeout,
        },
        "capture": {
            "maxDepth": args.max_depth,
            "maxChildren": args.max_children,
            "accessibilityTimeout": args.accessibility_timeout,
            "screenshotTimeout": args.screenshot_timeout,
        },
        "target": target,
        "bucket": bucket,
        "paths": {key: str(value) for key, value in paths.items()},
    }


def capture_profile_options(bucket, context):
    options = []
    for profile_id in bucket.get("captureProfiles") or []:
        profile = CAPTURE_PROFILES.get(profile_id)
        if not isinstance(profile, dict):
            raise ValueError(f"unknown capture profile in catalog: {profile_id}")
        profile_context = dict(context)
        profile_context["profile"] = profile
        rendered = render_template(profile.get("args") or [], profile_context)
        options.extend(str(item) for item in rendered)
    return options


def capture_sample(appshot, target, bucket, paths, args):
    command = [appshot, "capture"]
    window_id = target["window"].get("windowID")
    if window_id:
        command += ["--window-id", str(window_id)]
    else:
        command += ["--bundle-id", target["bundleID"], "--window-title", target["title"]]
    context = capture_context(args, target, bucket, paths)
    command += [str(item) for item in render_template(TRAINING_DEFAULTS["captureArgs"], context)]
    command += capture_profile_options(bucket, context)
    run(command, timeout=args.command_timeout)
    return json.loads(paths["raw"].read_text(encoding="utf-8"))


def target_from_capture(path, capture):
    app = capture.get("targetApplication") or capture.get("currentApplication") or capture.get("frontmostApplication") or {}
    window = capture.get("currentWindow") or capture.get("frontmostWindow") or capture.get("primaryWindow") or {}
    bundle_id = app.get("bundleIdentifier") or ""
    app_name = app.get("localizedName") or app.get("name") or bundle_id or "Unknown app"
    title = window.get("title") or capture.get("windowTitle") or pathlib.Path(path).stem
    return {
        "appName": app_name,
        "bundleID": bundle_id,
        "pid": app.get("processIdentifier"),
        "window": window,
        "title": title,
        "source": "replay-raw-dir",
        "sensitive": is_sensitive(bundle_id, title),
        "replayCapturePath": pathlib.Path(path),
    }


def replay_targets(args):
    raw_dir = pathlib.Path(args.replay_raw_dir).expanduser()
    captures = []
    for path in sorted(raw_dir.glob("*.json")):
        capture = json.loads(path.read_text(encoding="utf-8"))
        target = target_from_capture(path, capture)
        if args.target_bundle and target["bundleID"] not in set(args.target_bundle):
            continue
        if target["sensitive"] and args.privacy_mode == "skip-sensitive":
            continue
        captures.append(target)
    return captures[: args.max_windows] if args.max_windows else captures


def record_sample(appshot, db_path, sample, anchors, notes):
    command = [
        appshot, "rules", "record-sample",
        "--db", str(db_path),
        "--sample-id", sample["sampleID"],
        "--capture-json", str(sample["paths"]["raw"]),
        "--codex-text", str(sample["paths"]["codex"]),
        "--screenshot", str(sample["paths"]["screenshot"]),
        "--app-bundle-id", sample["bundleID"],
        "--window-title", sample["title"],
        "--notes", json.dumps(notes, ensure_ascii=False, sort_keys=True),
    ]
    for anchor in anchors:
        command += ["--anchor", anchor]
    run_json(command)


def select_best_versions(appshot, db_path, conn):
    rows = conn.execute(
        """
        SELECT bucket_id, rule_id, rule_version, AVG(score) avg_score, AVG(anchor_recall) avg_recall, COUNT(*) count
        FROM rule_run_metrics
        GROUP BY bucket_id, rule_id, rule_version
        ORDER BY bucket_id ASC, avg_score DESC, avg_recall DESC, count DESC
        """
    ).fetchall()
    selected = {}
    for bucket_id, rule_id, version, avg_score, avg_recall, count in rows:
        selected.setdefault(bucket_id, {
            "bucketID": bucket_id,
            "ruleID": rule_id,
            "ruleVersion": version,
            "avgScore": avg_score,
            "avgRecall": avg_recall,
            "sampleCount": count,
        })
    for bucket_id, item in selected.items():
        conn.commit()
        item["selectionEvent"] = run_json([
            appshot,
            "rules",
            "select",
            "--db",
            str(db_path),
            "--bucket-id",
            bucket_id,
            "--rule-id",
            item["ruleID"],
            "--version",
            str(item["ruleVersion"]),
        ])
    return list(selected.values())


def main():
    parser = argparse.ArgumentParser(description="Train AppShot JSON rules against real local app captures.")
    parser.add_argument("--appshot-bin", default=".build/debug/appshot")
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG_PATH), help="Path to the JSON rule strategy catalog.")
    parser.add_argument("--db", default=str(pathlib.Path.home() / "Library/Application Support/AppShot/rules.sqlite"))
    parser.add_argument("--output-dir", default="artifacts/rule-training")
    parser.add_argument("--replay-raw-dir", help="Replay existing capture JSON files instead of live window capture.")
    parser.add_argument("--privacy-mode", choices=["skip-sensitive", "include-sensitive"], default="skip-sensitive")
    parser.add_argument("--all-visible", action="store_true")
    parser.add_argument("--all-apps", action="store_true", help="Train every visible app, synthesizing generic per-app buckets from JSON.")
    parser.add_argument("--target-bundle", action="append", default=[])
    parser.add_argument("--max-windows", type=int, default=0)
    parser.add_argument("--min-area", type=int, default=40000)
    parser.add_argument("--max-rule-versions", type=int, default=4)
    parser.add_argument("--max-anchors", type=int, default=24)
    parser.add_argument("--max-depth", type=int, default=60)
    parser.add_argument("--max-children", type=int, default=700)
    parser.add_argument("--accessibility-timeout", type=int, default=20)
    parser.add_argument("--screenshot-timeout", type=int, default=6)
    parser.add_argument("--electron-timeout", type=int, default=8)
    parser.add_argument("--browser-dom-timeout", type=int, default=8)
    parser.add_argument("--command-timeout", type=int, default=100)
    args = parser.parse_args()

    catalog = load_catalog(args.catalog)
    appshot = str(pathlib.Path(args.appshot_bin))
    db_path = pathlib.Path(args.db).expanduser()
    run_id = stamp()
    out_dir = pathlib.Path(args.output_dir) / run_id
    raw_dir = out_dir / "raw"
    output_dir = out_dir / "rule-outs"
    rule_dir = out_dir / "rules"
    raw_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    run_json([appshot, "rules", "init", "--db", str(db_path)])
    conn = sqlite3.connect(db_path)
    rule_artifacts = []
    for bucket in BUCKETS:
        ensure_bucket(conn, bucket)
        for variant in bucket.get("variants") or []:
            rule_artifacts.append(upsert_rule(appshot, db_path, rule_json(bucket, variant), rule_dir))

    if args.replay_raw_dir:
        targets = replay_targets(args)
        windows = {
            "schemaVersion": 1,
            "source": "replay-raw-dir",
            "rawDir": str(pathlib.Path(args.replay_raw_dir).expanduser()),
            "captureCount": len(targets),
        }
    else:
        windows = run_json([appshot, "list-windows", "--pretty"], timeout=args.command_timeout)
        targets = collect_windows(windows, args)
    (out_dir / "windows.json").write_text(json.dumps(windows, ensure_ascii=False, indent=2), encoding="utf-8")
    samples, failures = [], []
    seeded_buckets = {bucket["bucketID"] for bucket in BUCKETS}

    for index, target in enumerate(targets, start=1):
        bucket = bucket_for_bundle(target["bundleID"], target["appName"])
        if bucket["bucketID"] not in seeded_buckets:
            ensure_bucket(conn, bucket)
            for variant in bucket.get("variants") or []:
                rule_artifacts.append(upsert_rule(appshot, db_path, rule_json(bucket, variant), rule_dir))
            seeded_buckets.add(bucket["bucketID"])

        label = slug(f"{index:02d}-{target['appName']}-{target['title'] or target['bundleID']}")
        sample_id = f"raw-{run_id}-{label}"
        paths = {
            "raw": raw_dir / f"{label}.json",
            "codex": raw_dir / f"{label}.codex.txt",
            "screenshot": raw_dir / f"{label}.png",
        }
        try:
            if target.get("replayCapturePath"):
                source_raw_path = pathlib.Path(target["replayCapturePath"])
                capture = json.loads(source_raw_path.read_text(encoding="utf-8"))
                paths["raw"].write_text(json.dumps(capture, ensure_ascii=False, indent=2), encoding="utf-8")
                source_screenshot = source_raw_path.with_suffix(".png")
                if source_screenshot.exists():
                    shutil.copyfile(source_screenshot, paths["screenshot"])
            else:
                capture = capture_sample(appshot, target, bucket, paths, args)
            codex_text = text_sources(capture)["codex"]
            paths["codex"].write_text(codex_text, encoding="utf-8")
            anchors, anchor_labels = make_anchors(capture, args.max_anchors)
            if not anchors and target["title"]:
                anchors = [re.escape(target["title"])]
                anchor_labels = [{"source": "title", "length": len(target["title"]), "baselineCodexContains": False}]

            sample = {
                "sampleID": sample_id,
                "bundleID": target["bundleID"],
                "appName": target["appName"],
                "title": target["title"],
                "bucketID": bucket["bucketID"],
                "sensitive": target["sensitive"],
                "paths": paths,
            }
            record_sample(appshot, db_path, sample, anchors, {
                "trainingRun": run_id,
                "privacyMode": args.privacy_mode,
                "sensitive": target["sensitive"],
                "catalogPath": str(pathlib.Path(args.catalog).expanduser()),
                "trainingMode": "replay-raw-dir" if args.replay_raw_dir else "live-capture",
                "replayRawPath": str(target.get("replayCapturePath") or ""),
                "ocrPolicy": TRAINING_DEFAULTS.get("ocrPolicy"),
                "anchorLabels": anchor_labels,
            })

            rule_ids = {variant["id"] for variant in bucket.get("variants") or [] if variant.get("id")}
            versions = fetch_rule_versions(conn, rule_ids, args.max_rule_versions)
            sample_runs = []
            for rule_id, version, rule in versions:
                output = apply_rule(capture, rule)
                output_path = output_dir / f"{sample_id}--{rule_id}-v{version}.txt"
                output_path.write_text(output["text"], encoding="utf-8")
                metric = evaluate_output(output["text"], codex_text, anchors, anchor_labels)
                run_row_id = insert_run(conn, sample, bucket, rule_id, version, output, metric, output_path)
                sample_runs.append({
                    "runID": run_row_id,
                    "ruleID": rule_id,
                    "ruleVersion": version,
                    "score": metric["score"],
                    "anchorRecall": metric["anchorRecall"],
                    "density": metric["density"],
                    "informationDensity": metric["informationDensity"],
                    "baselineRecall": metric["baselineRecall"],
                    "improvement": metric["improvement"],
                })
            best = max(sample_runs, key=lambda item: (item["score"], item["anchorRecall"], item["informationDensity"], item["density"])) if sample_runs else None
            samples.append({
                "sampleID": sample_id,
                "bundleID": target["bundleID"],
                "appName": target["appName"],
                "title": target["title"],
                "bucketID": bucket["bucketID"],
                "sensitive": target["sensitive"],
                "anchorCount": len(anchors),
                "bestRun": best,
                "rawPath": str(paths["raw"]),
                "screenshotPath": str(paths["screenshot"]),
            })
            best_text = "none" if not best else f"{best['score']:.2f}/{best['anchorRecall']:.2f}/d{best['density']:.2f}/id{best['informationDensity']:.2f}"
            print(
                f"[train] {index:02d} {target['bundleID']} bucket={bucket['bucketID']} "
                f"anchors={len(anchors)} best={best_text} sensitive={target['sensitive']}",
                flush=True,
            )
        except Exception as exc:
            failures.append({
                "sampleID": sample_id,
                "bundleID": target["bundleID"],
                "appName": target["appName"],
                "title": target["title"],
                "bucketID": bucket["bucketID"],
                "sensitive": target["sensitive"],
                "error": str(exc),
            })
            print(f"[train:failed] {target['bundleID']} {target['title']!r}: {exc}", file=sys.stderr, flush=True)

    selected = select_best_versions(appshot, db_path, conn)
    report = {
        "schemaVersion": 2,
        "trainingRun": run_id,
        "databasePath": str(db_path),
        "catalogPath": str(pathlib.Path(args.catalog).expanduser()),
        "catalogSchemaVersion": catalog.get("schemaVersion"),
        "ruleOutputKind": "upsertable-json-rule",
        "ruleArtifactFormat": "json",
        "ruleDirectory": str(rule_dir),
        "renderedRuleCount": len(rule_artifacts),
        "ruleArtifacts": rule_artifacts,
        "outputDir": str(out_dir),
        "trainingMode": "replay-raw-dir" if args.replay_raw_dir else "live-capture",
        "replayRawDir": str(pathlib.Path(args.replay_raw_dir).expanduser()) if args.replay_raw_dir else None,
        "privacyMode": args.privacy_mode,
        "targetCount": len(targets),
        "sampleCount": len(samples),
        "failureCount": len(failures),
        "selectedStrategies": selected,
        "samples": samples,
        "failures": failures,
    }
    report_path = out_dir / "rule-training-report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "trainingRun": run_id,
        "databasePath": str(db_path),
        "reportPath": str(report_path),
        "ruleOutputKind": report["ruleOutputKind"],
        "ruleArtifactFormat": report["ruleArtifactFormat"],
        "ruleDirectory": report["ruleDirectory"],
        "renderedRuleCount": report["renderedRuleCount"],
        "trainingMode": report["trainingMode"],
        "replayRawDir": report["replayRawDir"],
        "sampleCount": len(samples),
        "failureCount": len(failures),
        "selectedStrategyCount": len(selected),
        "privacyMode": args.privacy_mode,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
