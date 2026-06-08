# Rule 训练演进过程

本文记录 2026-06-08 这轮 all-app rule gate 如何从低分和一次 capture crash，演进到全 app 过线，并且保持训练输出仍然是可更新的 JSON rule，而不是 hard-coded output。

## 一句话版

这次演进先把“采集稳定性”和“规则有效性”拆开，再修掉 AI WeChat 的 AX 几何崩溃，最后用 JSON rule 调整 anchor、排序、行数和长行压缩，把所有可见 app 的 selected score 拉到 0.85 以上。

## 三句话版

第一次 all-app 训练暴露了两个主要矛盾：AI WeChat Desktop 在 AX 元素去重时崩溃，多个 app 虽然 anchor recall 接近或等于 1.00，但 information density 太低。崩溃问题在通用采集层解决，有效性问题通过 JSON rule 的 `anchorRejectRegex`、`dropRegex`、`importanceBoostRegex`、line caps 和 `transport.maxLineChars` 解决。最终 live gate 为 17 个样本、0 个失败、selected 最低分 0.9338，且训练摘要仍保持 `ruleOutputKind: upsertable-json-rule` 和 `ruleArtifactFormat: json`。

## 约束

- 目标分数必须高于 0.85。
- 训练输出必须是 rule-driven JSON，不能把结果 hardcode 到代码里。
- OCR 只能作为 teacher/evaluator 信号，不能作为 student output source。
- 敏感本地 capture 可以用于本地训练和 replay，但 raw artifacts 不提交。
- 最终结果必须覆盖当前所有可见 app，而不是只调过几个已知 bucket。

## 起点：第一次全 app 训练

第一次 live all-app training 给出了有用证据，但还不能作为 release gate。

| 观察项 | 证据 |
| --- | --- |
| 训练模式 | 当前可见窗口 live capture |
| 样本数 | 22 recorded samples |
| 失败数 | 2 failures |
| 崩溃对象 | `dev.agentdocker.aiwechatdesktop` SIGTRAP |
| 低分样本 | Codex / `electron-chat` selected score 0.6944 |
| 低分样本 | VS Code log window selected score 0.8038 |
| 主要模式 | 多数低分样本 recall 高，但 density 低 |

这里最关键的判断是：问题不是一种。AI WeChat 是 capture stability 问题；Codex、VS Code、browser、generic apps 更多是 rule ranking 和 density 问题。

## 第一阶段：先修采集稳定性

AI WeChat 暴露了异常 AX geometry。Swift 在 AX element/window dedupe 时把非有限 `Double`/`CGFloat` 转成 `Int`，导致运行时崩溃。

修复方式是通用的：

- 增加 `stableAXGeometryInt(_:)`。
- `axElementID(_:)` 中遇到 NaN/Inf position 或 size 时跳过该几何片段。
- `accessibilityWindowDedupeKey(_:)` 使用同样的安全转换。

这个修复没有写任何 app-specific output 逻辑，只让采集层在 macOS AX 暴露坏几何值时不崩。

## 第二阶段：保持输出仍然是 JSON Rule

用户约束很明确：训练结果必须是一堆可 upsert/update 的 rule JSON，而不是 hardcode。为了解决低密度长行问题，新增的是一个通用 rule interpreter 字段：

```json
{
  "action": {
    "transport": {
      "maxLineChars": 260,
      "preserveRaw": false
    }
  }
}
```

它的落点有三处：

- `scripts/train_local_app_rules.py`：训练和 replay 时解释 `transport.maxLineChars`。
- `Sources/AppShotCore/AppShotRules.swift`：Swift runtime 用同样规则执行。
- `scripts/verify_rule_governance.py`：加入 smoke test，确保长行截断由 JSON rule 控制。

这个字段是通用能力。具体哪个 app/bucket 使用、使用多大上限，都仍然写在 `rules/seed/local-app-strategies.json` 里。

## 第三阶段：重新问数据

一开始最直觉的问题是“是不是输出太长”。但这不是好问题，因为有些低分其实来自 teacher anchor 噪声，有些来自排序，有些来自长行 token 成本。

后来改问这些问题：

- 低分样本是漏了关键 anchor，还是只是带了太多低价值行？
- teacher 是否把动态计时、toolbar、tip、随机 token 当成训练目标？
- OCR 看到的是 AX blind spot，还是不应该进入 student output 的视觉噪声？
- 这个改动提升的是最低 selected sample，还是只把平均分做高了？

这些问题把规则演进带到了正确方向。

| 问题 | JSON rule 层面的处理 |
| --- | --- |
| `已持续 3m 39s` 这类动态计时 | 加入 anchor/drop rejection regex |
| VS Code toolbar/tip 文案 | 加入 anchor/drop rejection regex |
| 长随机 credential/token value | 加入 anchor/drop rejection regex |
| Browser / VS Code 长行 | 使用 `transport.maxLineChars` |
| VS Code 日志、代码、任务行需要提权 | 使用 `importanceBoostRegex` |
| Electron chat 当前任务行排序不够靠前 | boost commands、URLs、open/readme/action text |
| Generic app 被系统菜单壳淹没 | 通过更紧 line cap 和 generic control boost 提高密度 |

关键原则是：如果 teacher anchor 本身不稳定或低语义，就用 JSON reject 掉它，而不是在输出里写死补偿。

## 第四阶段：先 Replay，再 Live

每轮改规则后，先 replay 固定 raw captures，再跑 live。这样可以区分“规则真的变好”还是“当前窗口刚好变了”。

这轮用了两组 replay：

- 上一批 raw capture：22 个样本。
- 同批 live raw capture：17 个样本。

选择规则时优先看 per-sample minimum score，而不是只看平均分。平均分高但某个 app/window 低于 0.85，仍然不能算过。

## Bucket 演进摘要

| Bucket | 演进内容 |
| --- | --- |
| `vscode-workbench` | 收紧到 50 selected lines，reject tips/toolbars/random values，boost log/code/task lines，启用 `maxLineChars`。 |
| `electron-chat` | 输出源收敛到 visible/accessibility，收紧到 60 lines，reject timers/image URLs/process-env noise，boost 当前命令、URL、打开文档等 action text。 |
| `browser-webpage` | 收紧到 80 selected lines，关闭 rich spillover，启用 `maxLineChars`。 |
| `wechat-chat` | 收紧到 50 selected lines，关闭 rich spillover，启用 `maxLineChars`。 |
| Generic app buckets | 分成 50-line balanced 和 15-line dense 两种策略，加入 menu/action/control boost。 |
| Capture core | 对非有限 AX geometry 做安全转换，避免 malformed bounds 触发 crash。 |

## 最终效果衡量

最终 live all-app gate 于 2026-06-08 完成：

| 检查项 | 结果 |
| --- | --- |
| Live all-app training | 17 个样本，0 个失败 |
| Selected-rule score | 最低 0.9338，平均 0.9804 |
| 同批 live raw replay | 17 个样本，最低 0.9410，平均 0.9827 |
| 上一批 raw capture replay | 22 个样本，最低 0.8559，平均 0.9850 |
| Rule 输出契约 | `ruleOutputKind: upsertable-json-rule`，`ruleArtifactFormat: json` |
| Governance / parity gate | `scripts/verify_rule_governance.py` 通过，`scripts/verify_codex_parity.sh` 通过 |

最终 live selected 低分样本如下：

| App / bucket | Score | Recall | Density | Information density |
| --- | ---: | ---: | ---: | ---: |
| Safari / `browser-webpage` | 0.9338 | 1.0000 | 0.3561 | 0.7122 |
| Codex / `electron-chat` | 0.9410 | 1.0000 | 0.3697 | 0.7393 |
| Feishu / `electron-chat` | 0.9416 | 1.0000 | 0.3708 | 0.7417 |
| Chrome / `browser-webpage` | 0.9623 | 1.0000 | 0.4127 | 0.8254 |
| VS Code / `vscode-workbench` | 0.9697+ | 1.0000 | 0.4289+ | 0.8577+ |
| AI WeChat Desktop / generic | 1.0000 | 1.0000 | 0.5470 | 1.0000 |

此前会触发 SIGTRAP 的 AI WeChat Desktop 最终 capture 成功，得分 1.0000。

## 可复现命令

Live all-app training：

```sh
rm -f /private/tmp/appshot-all-apps-verified.sqlite
python3 scripts/train_local_app_rules.py \
  --appshot-bin .build/debug/appshot \
  --db /private/tmp/appshot-all-apps-verified.sqlite \
  --output-dir artifacts/rule-training-all-apps \
  --all-apps \
  --privacy-mode include-sensitive \
  --max-windows 80 \
  --command-timeout 45 \
  --accessibility-timeout 20 \
  --screenshot-timeout 10
```

Selected-rule score query：

```sh
sqlite3 /private/tmp/appshot-all-apps-verified.sqlite "
select
  min(round(m.score,4)),
  avg(m.score),
  count(*)
from rule_run_metrics m
join rule_strategy_buckets b
  on b.bucket_id=m.bucket_id
 and b.selected_rule_id=m.rule_id
 and b.selected_rule_version=m.rule_version;
"
```

Governance 和 parity：

```sh
python3 scripts/verify_rule_governance.py \
  --appshot-bin .build/debug/appshot \
  --catalog rules/seed/local-app-strategies.json

scripts/verify_codex_parity.sh
```

## 之后迭代要保留的原则

- OCR 默认只做 teacher/evaluator，不用它直接填 student output。
- 先 replay 固定 raw captures，再相信 live improvement。
- 优先优化最低 selected score，平均分只是第二指标。
- app-specific ranking 行为写进 JSON 的 `importanceBoostRegex`、`dropRegex`、caps 和 transport settings。
- 只有当能力足够通用、且可被 rule 控制时，才扩展 interpreter。
- 不提交敏感 local raw captures。

## Commit Trail

- `b9fa5fe Improve all-app rule training gates`：稳定性修复、`maxLineChars` 解释器、JSON strategy tuning、governance check。
- `6abd03d Document latest rule gate metrics`：README 效果衡量摘要。
