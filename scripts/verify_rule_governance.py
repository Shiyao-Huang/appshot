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
    assert_true(catalog.get("captureProfiles"), "catalog must declare named captureProfiles")

    appshot = str(pathlib.Path(args.appshot_bin))
    with tempfile.TemporaryDirectory(prefix="appshot-rule-governance.") as tmp_raw:
        tmp = pathlib.Path(tmp_raw)
        db_path = tmp / "rules.sqlite"
        rule_path = tmp / "rule.json"
        patch_path = tmp / "patch.json"
        capture_path = tmp / "capture.json"
        codex_path = tmp / "codex.txt"
        anchors_path = tmp / "anchors.json"
        student_path = tmp / "student.txt"

        rule = rules[0]
        write_json(rule_path, rule)
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
        assert_true(evaluate["anchorRecall"] == 1.0, "student output should recover all anchors")
        assert_true(evaluate["baselineRecall"] < evaluate["anchorRecall"], "rule output should improve baseline recall")

        history = run_json([appshot, "rules", "history", "--db", str(db_path), "--id", rule["id"], "--limit", "10"])
        assert_true(len(history.get("versions", [])) >= 2, "history should include rule versions")
        assert_true(any(event.get("action") == "patch" for event in history.get("events", [])), "history missing patch event")

        print(json.dumps({
            "status": "ok",
            "catalogSchemaVersion": catalog.get("schemaVersion"),
            "renderedRuleCount": len(rules),
            "smokeRuleID": rule["id"],
            "anchorRecall": evaluate["anchorRecall"],
            "baselineRecall": evaluate["baselineRecall"],
            "outputSource": evaluate.get("outputSource"),
            "databasePath": str(db_path),
        }, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
