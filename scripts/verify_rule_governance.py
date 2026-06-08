#!/usr/bin/env python3
import argparse
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parent.parent
TRAINER_PATH = ROOT / "scripts" / "train_local_app_rules.py"
CATALOG_PATH = ROOT / "rules" / "seed" / "local-app-strategies.json"


def load_trainer():
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("appshot_rule_trainer", TRAINER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_json(command):
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    return json.loads(result.stdout)


def run_json_tail(command):
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    decoder = json.JSONDecoder()
    text = result.stdout
    for index, char in enumerate(text):
        if char != "{":
            continue
        try:
            payload, end = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if text[index + end:].strip() == "":
            return payload
    raise ValueError(f"command did not end with a JSON object: {command}\n{text}")


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def assert_true(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    parser = argparse.ArgumentParser(description="Verify AppShot rule governance CLI and JSON-rule schema end-to-end.")
    parser.add_argument("--appshot-bin", default=str(ROOT / ".build" / "debug" / "appshot"))
    parser.add_argument("--catalog", default=str(CATALOG_PATH))
    args = parser.parse_args()

    trainer = load_trainer()
    catalog = trainer.load_catalog(args.catalog)
    rules = [trainer.rule_json(bucket, variant) for bucket in trainer.BUCKETS for variant in bucket.get("variants", [])]
    assert_true(rules, "catalog rendered no rules")
    assert_true(
        not any("ocr" in (rule.get("action", {}).get("sources") or []) for rule in rules),
        "default rendered rules must not output OCR",
    )
    assert_true(
        all((rule.get("action") or {}).get("ocrPolicy") == "teacher-only" for rule in rules),
        "rendered rules must keep OCR teacher-only",
    )
    assert_true(
        not any((rule.get("action") or {}).get("fallbackOCR") for rule in rules),
        "rendered rules must not enable OCR fallback as output",
    )
    assert_true(catalog.get("captureProfiles"), "catalog must declare named captureProfiles")
    anchor_caps = (catalog.get("trainingDefaults") or {}).get("anchorSourceCaps") or {}
    assert_true(anchor_caps.get("ocr", 99) < 24, "catalog must cap OCR teacher anchors below the full anchor budget")
    assert_true((catalog.get("trainingDefaults") or {}).get("anchorRejectRegex"), "catalog must declare low-value anchor rejection regex")
    capped_rule = json.loads(json.dumps(rules[0]))
    capped_rule.setdefault("action", {})
    capped_rule["action"]["sources"] = ["visible"]
    capped_rule["action"]["keepRegex"] = [".{4,}"]
    capped_rule["action"]["dropRegex"] = []
    capped_rule["action"]["transport"] = {
        "format": "toon",
        "maxImportantLines": 1,
        "maxRichLines": 0,
        "preserveRaw": True,
    }
    capped_output = trainer.apply_rule({
        "accessibility": {
            "visibleText": "alpha visible\nbeta visible\ngamma visible\n",
            "text": "",
            "documentReferences": [],
        },
        "ocr": {"text": "alpha visible\nbeta visible\ngamma visible\n"},
    }, capped_rule)
    assert_true(capped_output["fullLineCount"] == 3, "density cap smoke did not see all source lines")
    assert_true(capped_output["selectedLineCount"] == 1, "density cap smoke did not cap selected output lines")
    assert_true(len(capped_output["text"].splitlines()) == 1, "plain text output must honor rule line caps")
    truncated_rule = json.loads(json.dumps(capped_rule))
    truncated_rule["action"]["transport"]["maxLineChars"] = 16
    truncated_rule["action"]["transport"]["maxImportantLines"] = 2
    truncated_output = trainer.apply_rule({
        "accessibility": {
            "visibleText": "alpha visible line with additional context\nbeta visible\n",
            "text": "",
            "documentReferences": [],
        },
        "ocr": {"text": ""},
    }, truncated_rule)
    assert_true("alpha visible..." in truncated_output["text"], "maxLineChars must be controlled by JSON rules")
    boosted_rule = json.loads(json.dumps(capped_rule))
    boosted_rule["action"]["transport"]["maxImportantLines"] = 1
    boosted_rule["action"]["importanceBoostRegex"] = [{"regex": "beta visible", "weight": 20}]
    boosted_output = trainer.apply_rule({
        "accessibility": {
            "visibleText": "alpha visible\nbeta visible\n",
            "text": "",
            "documentReferences": [],
        },
        "ocr": {"text": ""},
    }, boosted_rule)
    assert_true(boosted_output["text"].strip() == "beta visible", "importanceBoostRegex must affect rule output ranking")
    anchor_capture = {
        "codex": {"text": ""},
        "accessibility": {
            "visibleText": "\n".join(f"visible useful line {index}" for index in range(12)),
            "text": "\n".join(f"accessibility useful line {index}" for index in range(12)),
            "documentReferences": [{"textPreview": "\n".join(f"document useful line {index}" for index in range(12))}],
        },
        "ocr": {
            "text": "\n".join([f"ocr useful teacher line {index}" for index in range(12)] + ["N2 361 31 31Az42", "*HIPPT"]),
            "observations": [],
        },
    }
    _, anchor_labels = trainer.make_anchors(anchor_capture, 24)
    label_counts = {}
    for label in anchor_labels:
        label_counts[label["source"]] = label_counts.get(label["source"], 0) + 1
    assert_true(label_counts.get("ocr", 0) <= anchor_caps["ocr"], "OCR anchors must respect catalog cap")
    assert_true(label_counts.get("visible", 0) > 0, "visible anchors should survive source balancing")
    assert_true(label_counts.get("accessibility", 0) > 0, "accessibility anchors should survive source balancing")
    assert_true(label_counts.get("document", 0) > 0, "document anchors should survive source balancing")
    reject_capture = {
        "codex": {"text": ""},
        "accessibility": {
            "visibleText": "962.9 MB\n2026年5月16日 18:38\nsemantic project row\n",
            "text": "",
            "documentReferences": [],
        },
        "ocr": {"text": ""},
    }
    reject_anchors, _ = trainer.make_anchors(reject_capture, 8)
    assert_true(not any("962" in anchor for anchor in reject_anchors), "pure size metadata must not become a training anchor")
    assert_true(not any("2026" in anchor for anchor in reject_anchors), "pure date metadata must not become a training anchor")
    assert_true(any("semantic" in anchor for anchor in reject_anchors), "semantic replacement anchor should survive rejection")
    teacher_gap_metric = trainer.evaluate_output(
        "alpha visible\n",
        "",
        ["alpha visible", "delta ocr only"],
        [
            {"source": "visible", "weight": 1.0},
            {"source": "ocr", "weight": 2.0},
        ],
    )
    assert_true(teacher_gap_metric["anchorRecall"] == 1.0, "student recall must exclude OCR-only teacher anchors")
    assert_true(teacher_gap_metric["teacherRecall"] == 0.5, "teacher recall must include OCR-only teacher anchors")
    assert_true(teacher_gap_metric["axGapCount"] == 1, "OCR-only teacher miss must remain visible as AX gap")
    assert_true(not teacher_gap_metric["missingAnchors"], "student missingAnchors must exclude OCR-only teacher anchors")

    appshot = str(pathlib.Path(args.appshot_bin))
    with tempfile.TemporaryDirectory(prefix="appshot-rule-governance.") as tmp_raw:
        tmp = pathlib.Path(tmp_raw)
        db_path = tmp / "rules.sqlite"
        rule_path = tmp / "rule.json"
        patch_path = tmp / "patch.json"
        boost_rule_path = tmp / "boost-rule.json"
        capture_path = tmp / "capture.json"
        codex_path = tmp / "codex.txt"
        anchors_path = tmp / "anchors.json"
        student_path = tmp / "student.txt"
        boost_student_path = tmp / "boost-student.txt"
        teacher_gap_anchors_path = tmp / "teacher-gap-anchors.json"
        teacher_gap_student_path = tmp / "teacher-gap-student.txt"

        rule = rules[0]
        write_json(rule_path, rule)
        cli_boost_rule = json.loads(json.dumps(capped_rule))
        cli_boost_rule["action"]["transport"]["maxImportantLines"] = 1
        cli_boost_rule["action"]["importanceBoostRegex"] = [{"regex": "beta visible", "weight": 20}]
        write_json(boost_rule_path, cli_boost_rule)
        write_json(patch_path, {"confidence": 0.73, "action": {"transport": {"maxImportantLines": 2}}})

        init_payload = run_json([appshot, "rules", "init", "--db", str(db_path)])
        assert_true("rules" in init_payload.get("tables", []), "rules table missing from init payload")

        upsert = run_json([appshot, "rules", "upsert", "--db", str(db_path), "--rule-json-file", str(rule_path)])
        assert_true(upsert["created"] is True and upsert["version"] == 1, "first upsert should create v1")

        patch = run_json([appshot, "rules", "patch", "--db", str(db_path), "--id", rule["id"], "--patch-json-file", str(patch_path)])
        assert_true(patch["updated"] is True and patch["version"] == 2, "patch should create v2")

        listed = run_json([appshot, "rules", "list", "--db", str(db_path), "--app-bundle-id", rule["match"]["appBundleIds"][0]])
        listed_ids = {item.get("id") for item in listed.get("rules", [])}
        assert_true(rule["id"] in listed_ids, "upserted rule missing from list")

        archive = run_json([appshot, "rules", "archive", "--db", str(db_path), "--id", rule["id"], "--reason", "smoke"])
        assert_true(archive["enabled"] is False, "archive did not disable rule")
        activate = run_json([appshot, "rules", "activate", "--db", str(db_path), "--id", rule["id"], "--reason", "smoke"])
        assert_true(activate["enabled"] is True, "activate did not enable rule")

        capture = {
            "targetApplication": {"bundleIdentifier": rule["match"]["appBundleIds"][0], "localizedName": "Rule Smoke"},
            "currentWindow": {"title": "Rule governance smoke"},
            "codex": {"text": "alpha visible\n"},
            "accessibility": {
                "visibleText": "alpha visible\nbeta visible\n",
                "text": "alpha visible\nbeta visible\n",
                "documentReferences": [{"textPreview": "gamma document"}],
            },
            "ocr": {
                "text": "beta visible\ngamma document\n",
                "observations": [
                    {"text": "beta visible", "confidence": 0.96, "boundingBox": {"height": 0.08}},
                    {"text": "gamma document", "confidence": 0.93, "boundingBox": {"height": 0.05}},
                ],
            },
        }
        write_json(capture_path, capture)
        codex_path.write_text(capture["codex"]["text"], encoding="utf-8")
        write_json(anchors_path, [
            {"regex": "alpha visible", "source": "visible", "weight": 1.0},
            {"regex": "beta visible", "source": "ocr", "weight": 2.0},
            {"regex": "gamma document", "source": "document", "weight": 1.5},
        ])

        sample_id = "rule-governance-smoke"
        record = run_json([
            appshot,
            "rules",
            "record-sample",
            "--db",
            str(db_path),
            "--sample-id",
            sample_id,
            "--capture-json",
            str(capture_path),
            "--codex-text",
            str(codex_path),
            "--anchor-json-file",
            str(anchors_path),
            "--app-bundle-id",
            rule["match"]["appBundleIds"][0],
            "--window-title",
            "Rule governance smoke",
            "--notes",
            "Synthetic local-only smoke sample.",
        ])
        assert_true(record["anchorCount"] == 3, "record-sample did not persist typed anchors")
        write_json(teacher_gap_anchors_path, [
            {"regex": "alpha visible", "source": "visible", "weight": 1.0},
            {"regex": "delta ocr only", "source": "ocr", "weight": 2.0},
        ])
        teacher_gap_student_path.write_text("alpha visible\n", encoding="utf-8")
        teacher_gap_sample_id = "rule-governance-teacher-gap"
        teacher_gap_record = run_json([
            appshot,
            "rules",
            "record-sample",
            "--db",
            str(db_path),
            "--sample-id",
            teacher_gap_sample_id,
            "--capture-json",
            str(capture_path),
            "--codex-text",
            str(codex_path),
            "--anchor-json-file",
            str(teacher_gap_anchors_path),
            "--app-bundle-id",
            rule["match"]["appBundleIds"][0],
            "--window-title",
            "Rule governance OCR teacher gap",
            "--notes",
            "Synthetic local-only OCR teacher gap smoke sample.",
        ])
        assert_true(teacher_gap_record["anchorCount"] == 2, "teacher-gap sample did not persist typed anchors")

        apply_payload = run_json([
            appshot,
            "rules",
            "apply",
            "--db",
            str(db_path),
            "--rule-json-file",
            str(rule_path),
            "--capture-json",
            str(capture_path),
            "--output",
            str(student_path),
        ])
        assert_true(apply_payload.get("lineCount", 0) >= 3, "rule apply did not extract expected lines")
        run_json([
            appshot,
            "rules",
            "apply",
            "--db",
            str(db_path),
            "--rule-json-file",
            str(boost_rule_path),
            "--capture-json",
            str(capture_path),
            "--output",
            str(boost_student_path),
        ])
        assert_true(boost_student_path.read_text(encoding="utf-8").strip() == "beta visible", "CLI importanceBoostRegex must affect rule output ranking")

        evaluate = run_json([
            appshot,
            "rules",
            "evaluate",
            "--db",
            str(db_path),
            "--sample-id",
            sample_id,
            "--output-text",
            str(student_path),
            "--metric-weights-json",
            json.dumps(catalog["trainingDefaults"]["metricWeights"], sort_keys=True),
        ])
        assert_true(evaluate["anchorRecall"] == 1.0, "student output should recover all student anchors")
        assert_true(evaluate["baselineRecall"] < evaluate["anchorRecall"], "rule output should improve baseline recall")
        teacher_gap_evaluate = run_json([
            appshot,
            "rules",
            "evaluate",
            "--db",
            str(db_path),
            "--sample-id",
            teacher_gap_sample_id,
            "--output-text",
            str(teacher_gap_student_path),
            "--metric-weights-json",
            json.dumps(catalog["trainingDefaults"]["metricWeights"], sort_keys=True),
        ])
        assert_true(teacher_gap_evaluate["anchorRecall"] == 1.0, "CLI student recall must exclude OCR-only teacher anchors")
        assert_true(teacher_gap_evaluate["teacherRecall"] == 0.5, "CLI teacher recall must include OCR-only teacher anchors")
        assert_true(teacher_gap_evaluate["axGapCount"] == 1, "CLI OCR-only miss must remain an AX gap")
        assert_true(not teacher_gap_evaluate["missingAnchors"], "CLI student missingAnchors must exclude OCR-only teacher anchors")

        history = run_json([appshot, "rules", "history", "--db", str(db_path), "--id", rule["id"], "--limit", "10"])
        assert_true(len(history.get("versions", [])) >= 2, "history should include rule versions")
        assert_true(any(event.get("action") == "patch" for event in history.get("events", [])), "history missing patch event")

        replay_raw_dir = tmp / "replay-raw"
        replay_raw_dir.mkdir()
        write_json(replay_raw_dir / "sample.json", capture)
        replay_payload = run_json_tail([
            sys.executable,
            str(TRAINER_PATH),
            "--appshot-bin",
            appshot,
            "--catalog",
            str(args.catalog),
            "--db",
            str(tmp / "replay.sqlite"),
            "--output-dir",
            str(tmp / "replay-out"),
            "--replay-raw-dir",
            str(replay_raw_dir),
            "--privacy-mode",
            "include-sensitive",
            "--max-windows",
            "1",
            "--command-timeout",
            "20",
        ])
        assert_true(replay_payload["trainingMode"] == "replay-raw-dir", "trainer replay smoke did not use replay mode")
        assert_true(replay_payload["sampleCount"] == 1, f"trainer replay smoke expected one sample: {replay_payload}")
        assert_true(replay_payload["failureCount"] == 0, f"trainer replay smoke reported failures: {replay_payload}")
        assert_true(replay_payload["ruleOutputKind"] == "upsertable-json-rule", "trainer replay output must stay JSON-rule based")

        print(json.dumps({
            "status": "ok",
            "ruleOutputKind": "upsertable-json-rule",
            "catalogSchemaVersion": catalog.get("schemaVersion"),
            "renderedRuleCount": len(rules),
            "smokeRuleID": rule["id"],
            "anchorRecall": evaluate["anchorRecall"],
            "baselineRecall": evaluate["baselineRecall"],
            "teacherGapRecall": teacher_gap_evaluate["teacherRecall"],
            "outputSource": evaluate.get("outputSource"),
            "databasePath": str(db_path),
        }, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
