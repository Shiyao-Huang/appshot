# AppShot Rule Benchmark Protocol

Rule benchmarks test whether JSON extraction rules improve AppShot output without
turning training into a script. The benchmark is a fixed corpus plus thresholds; agents
run it by calling AppShot tools.

## Objective

A rule version must preserve useful on-screen information while keeping token cost low.
High recall alone is not enough: dumping a full Accessibility tree should lose to a
smaller output with comparable visual recall.

Primary metrics:

- `accessibilityRecall`: fraction of benchmark anchors matched by the AX student output.
- `informationDensity`: useful anchor payload per output character, adjusted for entropy
  and duplicate lines.
- `axGap`: OCR/visible teacher anchors missed by the AX student output.
- `ocrOracleRecall`: teacher-anchor recall, used only to diagnose AX blind spots.
- `score`: the recall and density blend returned by `appshot rules evaluate`.

Secondary metrics:

- `charCount`, `lineCount`, `transportLineCount`: token-cost proxies.
- `sources`: must not contain `ocr`.
- capture/apply/evaluate latency, when the agent records timings.
- privacy leak count for suite-defined forbidden patterns.

## Benchmark Tiers

Use four tiers, from cheap to realistic:

- `fixture`: committed synthetic captures with no private data. This is the CI-safe gate.
- `local-smoke`: current machine apps, `privacyMode=skip-sensitive`, quick regression.
- `local-sensitive`: opt-in real windows such as WeChat, Feishu, Codex, browsers. Never
  commit raw captures from this tier.
- `release-gate`: fixture + local-smoke + any explicitly approved sensitive suite before
  selecting a production bucket or shipping a release.

## Suite Shape

Benchmark suites are JSON. Keep the raw captures and anchors as separate files so agents
can rerun the same samples against many rule versions.

```json
{
  "schemaVersion": 1,
  "suiteID": "local-smoke-20260607",
  "privacyMode": "skip-sensitive",
  "metricWeights": {
    "weightedVisualRecall": 0.55,
    "anchorRecall": 0.25,
    "informationDensity": 0.2
  },
  "thresholds": {
    "minAccessibilityRecall": 0.75,
    "minInformationDensity": 0.08,
    "maxAxGapCount": 6,
    "maxCharCount": 18000,
    "maxRegression": 0.03
  },
  "cases": [
    {
      "caseID": "vscode-terminal",
      "bucketID": "vscode-workbench",
      "appBundleID": "com.microsoft.VSCode",
      "captureJSONPath": "artifacts/bench/vscode-terminal/capture.json",
      "codexTextPath": "artifacts/bench/vscode-terminal/codex.txt",
      "anchorsPath": "artifacts/bench/vscode-terminal/anchors.json",
      "rules": ["vscode-workbench-text"]
    }
  ]
}
```

Anchor files use:

```json
[
  {"regex": "Terminal \\(⌃`\\)", "source": "visible", "weight": 1.2, "required": true},
  {"regex": "Crunched for", "source": "ocr", "weight": 2.0, "required": true}
]
```

## Runner Loop

The agent is the benchmark runner:

1. Read the suite JSON.
2. For each case, call `appshot rules record-sample` with `--anchor-json-file`.
3. For every listed candidate rule, call `appshot rules apply`.
4. Call `appshot rules evaluate --output-text ... --metric-weights-json ...`.
5. Compare each result to suite thresholds and to the currently selected rule for the
   bucket.
6. Call `appshot rules measure` for aggregate ranking.
7. Call `appshot rules improvements --status open` and attach benchmark evidence to any
   missed anchors, low-density outputs, or privacy failures.
8. Select a rule only when it passes thresholds and does not regress beyond
   `maxRegression`.

## Pass Criteria

A candidate passes a case only when all are true:

- `sources` from `rules apply` excludes `ocr`.
- `accessibilityRecall >= minAccessibilityRecall`.
- `informationDensity >= minInformationDensity`.
- `axGapCount <= maxAxGapCount`.
- `charCount <= maxCharCount`.
- no suite forbidden privacy pattern is present in the student output.
- `score` is not worse than the selected baseline by more than `maxRegression`.

For releases, require all fixture cases and local-smoke cases to pass. Sensitive local
cases may block release only when the user explicitly opted in to include that benchmark.

## Why This Works

The benchmark freezes the raw evidence while letting agents mutate only JSON rules. That
makes rule changes comparable across versions, apps, and privacy tiers. OCR remains a
teacher signal, TOON remains the model-facing transport, and the richer non-visual
capture stays local for diagnosis rather than being thrown away.
