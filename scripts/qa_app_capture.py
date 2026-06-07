#!/usr/bin/env python3
import argparse
import json
import pathlib
import subprocess
import sys
from datetime import datetime, timezone


def run_json(command):
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    return json.loads(result.stdout)


def run_text(command):
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    return result.stdout


def find_window(appshot, bundle_id, window_title):
    payload = run_json([appshot, "list-windows", "--pretty"])
    matches = []
    for app in payload.get("applications", []):
        if bundle_id and app.get("bundleIdentifier") != bundle_id:
            continue
        for collection, source in (("windows", "cgWindow"), ("accessibilityWindows", "accessibilityWindow")):
            for window in app.get(collection, []):
                title = window.get("title", "")
                if window_title and window_title not in title:
                    continue
                target = dict(window)
                target.setdefault("source", source)
                matches.append((app, target))

    if not matches:
        raise SystemExit(f"No window matched bundle={bundle_id!r} title={window_title!r}")
    return matches[0]


def walk(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            if isinstance(child, (dict, list)):
                yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def hierarchy_blob(node):
    parts = []
    for item in walk(node):
        if not isinstance(item, dict):
            continue
        for key in ("role", "title", "description", "value", "identifier", "roleDescription", "placeholderValue"):
            raw = item.get(key)
            if raw not in (None, ""):
                parts.append(str(raw))
    return "\n".join(parts)


def image_size(path):
    try:
        output = run_text(["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)])
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None

    width = height = None
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("pixelWidth:"):
            width = int(line.split(":", 1)[1].strip())
        elif line.startswith("pixelHeight:"):
            height = int(line.split(":", 1)[1].strip())
    if width is None or height is None:
        return None
    return width, height


def bounds_size(window):
    bounds = window.get("bounds") or {}
    width = bounds.get("width")
    height = bounds.get("height")
    if not isinstance(width, (int, float)) or not isinstance(height, (int, float)):
        return None
    if width <= 0 or height <= 0:
        return None
    return int(round(width)), int(round(height))


def image_matches_window_bounds(size, window, tolerance):
    expected = bounds_size(window)
    if size is None or expected is None:
        return False, f"image={size} bounds={expected}"

    image_width, image_height = size
    bounds_width, bounds_height = expected
    candidates = []
    for scale in (1, 2, 3):
        target_width = bounds_width * scale
        target_height = bounds_height * scale
        max_extra = tolerance * scale
        width_extra = image_width - target_width
        height_extra = image_height - target_height
        candidates.append(
            f"{scale}x target={target_width}x{target_height} extra={width_extra}x{height_extra}"
        )
        if 0 <= width_extra <= max_extra and 0 <= height_extra <= max_extra:
            return True, candidates[-1]

    return False, "; ".join(candidates)


def add_check(checks, name, passed, detail=""):
    checks.append({"name": name, "passed": bool(passed), "detail": detail})


def main():
    parser = argparse.ArgumentParser(description="Capture a macOS app/window and verify screenshot, OCR text, AX text, and AX hierarchy.")
    parser.add_argument("--appshot-bin", default=".build/debug/appshot")
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--window-title", required=True)
    parser.add_argument("--output-dir", default="artifacts/app-capture-qa")
    parser.add_argument("--label", default=None)
    parser.add_argument("--max-depth", default="25")
    parser.add_argument("--max-children", default="260")
    parser.add_argument("--accessibility-timeout", default="8")
    parser.add_argument("--screenshot-timeout", default="3")
    parser.add_argument("--image-border-tolerance", type=int, default=128)
    parser.add_argument("--expect-ax", action="append", default=[])
    parser.add_argument("--expect-visible", action="append", default=[])
    parser.add_argument("--expect-ocr", action="append", default=[])
    parser.add_argument("--expect-hierarchy", action="append", default=[])
    parser.add_argument("--report-json", action="store_true")
    args = parser.parse_args()

    appshot = str(pathlib.Path(args.appshot_bin))
    app, window = find_window(appshot, args.bundle_id, args.window_title)
    window_id = window.get("windowID")
    target_title = window.get("title") or args.window_title

    label = args.label or f"{app.get('localizedName', 'app')}-{window_id or target_title}"
    safe_label = "".join(ch if ch.isalnum() or ch in "-_" else "-" for ch in label)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output_dir = pathlib.Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    json_path = output_dir / f"{safe_label}-{stamp}.json"
    screenshot_path = output_dir / f"{safe_label}-{stamp}.png"
    report_path = output_dir / f"{safe_label}-{stamp}.report.json"

    capture_command = [
        appshot,
        "capture",
        "--max-depth",
        args.max_depth,
        "--max-children",
        args.max_children,
        "--accessibility-timeout",
        args.accessibility_timeout,
        "--screenshot-timeout",
        args.screenshot_timeout,
        "--include-screenshot",
        "--include-ocr",
        "--screenshot",
        str(screenshot_path),
        "--output",
        str(json_path),
        "--pretty",
    ]
    if window_id:
        capture_command[2:2] = ["--window-id", str(window_id)]
    else:
        capture_command[2:2] = ["--bundle-id", args.bundle_id, "--window-title", target_title]

    subprocess.run(capture_command, check=True, text=True, capture_output=True)
    capture = json.loads(json_path.read_text())

    checks = []
    permissions = capture.get("permissions", {})
    add_check(
        checks,
        "permissions",
        permissions.get("accessibility") is True and permissions.get("screenRecording") is True,
        json.dumps(permissions, ensure_ascii=False, sort_keys=True),
    )

    primary_window = capture.get("primaryWindow", {})
    primary_title = primary_window.get("title", "")
    target_window_matches = args.window_title in primary_title
    if window_id:
        target_window_matches = target_window_matches and primary_window.get("windowID") == window_id
    add_check(
        checks,
        "target window",
        target_window_matches,
        f"{primary_title} #{primary_window.get('windowID')} source={primary_window.get('source', 'cgWindow')}",
    )

    screenshot = capture.get("screenshot", {})
    size = image_size(screenshot_path)
    add_check(
        checks,
        "screenshot captured",
        screenshot.get("captured") is True and screenshot_path.exists() and size is not None and size[0] > 0 and size[1] > 0,
        f"{screenshot_path} {size}",
    )
    screenshot_matches_target = pathlib.Path(screenshot.get("path", "")) == screenshot_path
    if window_id:
        screenshot_matches_target = screenshot_matches_target and screenshot.get("windowID") == window_id
    else:
        screenshot_matches_target = screenshot_matches_target and screenshot.get("captureMode") == "bounds"
    add_check(
        checks,
        "screenshot matches target window",
        screenshot_matches_target,
        f"jsonPath={screenshot.get('path')} windowID={screenshot.get('windowID')} mode={screenshot.get('captureMode')}",
    )
    image_bounds_ok, image_bounds_detail = image_matches_window_bounds(size, primary_window, args.image_border_tolerance)
    add_check(
        checks,
        "screenshot size matches window bounds",
        image_bounds_ok,
        image_bounds_detail,
    )

    ocr = capture.get("ocr", {})
    ocr_text = ocr.get("text") or ""
    add_check(
        checks,
        "ocr available",
        ocr.get("available") is True and ocr.get("observationCount", 0) > 0,
        f"count={ocr.get('observationCount')}",
    )

    ax = capture.get("accessibility", {})
    ax_text = ax.get("text") or ""
    visible_text = ax.get("visibleText") or ""
    target_window = ax.get("targetWindow") or {}
    target_ax_title = target_window.get("title", "")
    target_ax_matches = args.window_title in target_ax_title
    if window_id:
        target_ax_matches = target_ax_matches and target_window.get("windowID") == window_id
    add_check(
        checks,
        "ax text available",
        ax.get("trusted") is True and ax.get("textLineCount", 0) > 0 and bool(ax_text.strip()),
        f"lines={ax.get('textLineCount')}",
    )
    add_check(
        checks,
        "visible text available",
        ax.get("trusted") is True and ax.get("visibleTextLineCount", 0) > 0 and bool(visible_text.strip()),
        f"lines={ax.get('visibleTextLineCount')}",
    )
    add_check(
        checks,
        "accessibility root is target window",
        ax.get("rootSource") == "targetWindow" and (ax.get("root") or {}).get("role") == "AXWindow",
        f"rootSource={ax.get('rootSource')} rootRole={(ax.get('root') or {}).get('role')}",
    )
    add_check(
        checks,
        "accessibility target window metadata",
        target_ax_matches,
        f"{target_ax_title} #{target_window.get('windowID')} source={target_window.get('source', 'cgWindow')}",
    )

    hierarchy = hierarchy_blob(ax)
    for expected in args.expect_ax:
        add_check(checks, f"ax text contains {expected}", expected in ax_text)
    for expected in args.expect_visible:
        add_check(checks, f"visible text contains {expected}", expected in visible_text)
    for expected in args.expect_ocr:
        add_check(checks, f"ocr text contains {expected}", expected in ocr_text)
    for expected in args.expect_hierarchy:
        add_check(checks, f"hierarchy contains {expected}", expected in hierarchy)

    report = {
        "label": label,
        "bundleIdentifier": args.bundle_id,
        "windowTitle": primary_window.get("title"),
        "windowID": window_id,
        "windowSource": window.get("source", "cgWindow"),
        "jsonPath": str(json_path),
        "screenshotPath": str(screenshot_path),
        "reportPath": str(report_path),
        "imageSize": size,
        "imageBorderTolerance": args.image_border_tolerance,
        "textLineCount": ax.get("textLineCount"),
        "visibleTextLineCount": ax.get("visibleTextLineCount"),
        "ocrObservationCount": ocr.get("observationCount"),
        "checks": checks,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    if args.report_json:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"QA report for {json_path}")
        for check in checks:
            status = "PASS" if check["passed"] else "FAIL"
            detail = f" {check['detail']}" if check.get("detail") else ""
            print(f"{status} - {check['name']}{detail}")
        print(f"report: {report_path}")
        print(f"screenshot: {screenshot_path}")

    if not all(check["passed"] for check in checks):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
