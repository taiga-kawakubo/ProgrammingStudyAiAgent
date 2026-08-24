# PROJECT_STRUCTURE

| 場所 | 何のためにあるか | 誰が更新するか | 学習者が編集してよいか |
| --- | --- | --- | --- |
| README.md | 利用者向けの入口と使い方を説明する | main Agentまたは保守者 | 原則いいえ |
| docs/ | 要件定義書など、開発前に読む文書を置く | main Agentまたは保守者 | 原則いいえ |
| AGENTS.md | AgentとサブAgentの責務を説明する | main Agentまたは保守者 | 原則いいえ |
| MISSION.md | ProgrammingAIの目的と方針を説明する | main Agentまたは保守者 | 原則いいえ |
| HARNESS_MAP.md | 全体接続を確認する地図 | main Agentまたは保守者 | 原則いいえ |
| PROJECT_STRUCTURE.md | ディレクトリと主要ファイルの役割を説明する | main Agentまたは保守者 | 原則いいえ |
| SMOKE_TEST.md | 最小フローと統合確認の手順を記録する | main Agentまたは保守者 | 原則いいえ |
| smoke-tests/ | ダミー検証や保存フローの実行結果を置く | main Agent | 原則いいえ |
| .codex/internal/ | 保守者向けの内部検証ハーネスと検証補助ファイルを置く | main Agentまたは保守者 | 原則いいえ |
| learning-cases/ | 日付ごとの一次学習記録を置く | main Agent | 原則いいえ |
| learning-logs/ | 確定学習ログを直下に置く | main Agent | 修正が必要な場合のみ |
| notebook/ | 日次傾向、learner-profile.md、Memory.mdを置く | main Agent | learner-profile.mdとMemory.mdは必要時に編集可 |
| .codex/state/ | current-term.tomlなどの進行状態を置く | main Agent | 原則いいえ |
| .codex/config.toml | 実際の設定値 | main Agentまたは学習者 | はい |
| .codex/config.defaults.toml | 設定チェック定義 | main Agentまたは保守者 | 原則いいえ |
| .codex/skills/ | Skill本文 | main Agentまたは保守者 | 原則いいえ |
| .codex/agents/mentor/ | mentor Agentの責務定義と専用MEMORYを置く | main Agent | 原則いいえ |

## `.codex/state/` の役割

`.codex/state/` は、学習者向けの学習ログではなく、main Agentが現在の学習状態を管理するための内部状態置き場である。

主に次の内容を扱う。

| 場所 | 役割 |
| --- | --- |
| `.codex/state/current-term.toml` | 現在進行中の学習ターム、分類、状態、次に待っている返答を記録する |
| `.codex/state/paused-terms.toml` | 中断中の学習タームを記録する |
| `.codex/state/daily-profile-rollover.toml` | 日付変更後の日次学習傾向作成が二重に走らないように、処理済み日付を記録する |
| `.codex/state/terms/` | 学習タームごとの質問、参照内容、回答下書き、ログ下書き、metadataを置く |

学習者に見せる記録は `learning-cases/`、確定学習ログは `learning-logs/`、学習傾向や苦手は `notebook/` に保存する。
`.codex/state/` は、これらの保存処理を安全に進めるための作業状態であり、手作業で編集または削除しない。

## `.codex/agents/mentor/` の役割

`.codex/agents/mentor/` は、mentorだけを独立Agentとして扱うための場所である。

| 場所 | 役割 |
| --- | --- |
| `.codex/agents/mentor/AGENT.md` | mentor Agentの責務、入力、出力、保存権限を説明する |
| `.codex/agents/mentor/MEMORY.md` | learning-casesとlearning-logsから抽出した苦手分析ログを保存する |

mentor専用MEMORYは、`notebook/Memory.md` とは役割が違う。
`.codex/agents/mentor/MEMORY.md` は苦手分析専用、`notebook/Memory.md` は質問傾向や学習者との関わり方を保存する場所として扱う。

## 原本の初期状態

`ProgrammingAI_v2 原本` は、他の人がコピーして使い始めるための初期テンプレートとして扱う。
原本にはAgent本体、Skill、設定、README、設計書、保守用検証ファイルを残す。

一方で、次のような個人の学習内容や進行状態は原本に残さない。

- `learning-cases/*.md`
- `learning-logs/*.md`
- `notebook/daily-learning-profiles/*.md`
- `notebook/learner-profile.md` 内の具体的な苦手傾向
- `notebook/Memory.md` 内の具体的な質問傾向
- `.codex/agents/mentor/MEMORY.md` 内の具体的な苦手分析ログ
- `.codex/state/terms/` 内のターム別作業状態
- `.codex/state/current-term.toml` の進行中ターム

原本を更新するときは、学習者個人のログを同期しない。
分類ガード、Skill、設計書、内部検証ハーネスなど、Agentの仕組みに関する変更だけを反映する。
