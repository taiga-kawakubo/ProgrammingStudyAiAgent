# PROJECT_STRUCTURE

| 場所 | 何のためにあるか | 誰が更新するか | 学習者が編集してよいか |
| --- | --- | --- | --- |
| README.md | 利用者向けの入口と使い方を説明する | main Agentまたは保守者 | 原則いいえ |
| docs/ | 要件定義書、保守ガイドなどを置く | main Agentまたは保守者 | 原則いいえ |
| AGENTS.md | AgentとサブAgentの責務を説明する | main Agentまたは保守者 | 原則いいえ |
| PROJECT_STRUCTURE.md | ディレクトリと主要ファイルの役割を説明する | main Agentまたは保守者 | 原則いいえ |
| SMOKE_TEST.md | 最小フローと統合確認の手順を記録する | main Agentまたは保守者 | 原則いいえ |
| .codex/hooks.json | CodexのUserPromptSubmit hookに日次処理scriptとinbox/outbox確認scriptを登録する | main Agentまたは保守者 | 原則いいえ |
| .codex/internal/scripts/ | hookから実行する機械的な補助scriptを置く | main Agentまたは保守者 | 原則いいえ |
| .codex/internal/validation/ | 設定値と保存済み分類ラベルの整合性を確認する最小チェッカーを置く | main Agentまたは保守者 | 原則いいえ |
| learning-cases/ | 日付ごとの一次学習記録を置く | main Agent | 原則いいえ |
| learning-cases/inbox/ | in_progressのLearning Caseへの分野別リンク集を置く | hook script | 原則いいえ |
| learning-cases/outbox/ | completedのLearning Caseへの分野別リンク集を置く | hook script | 原則いいえ |
| learning-logs/ | 確定学習ログを直下に置く | main Agent | 修正が必要な場合のみ |
| notebook/ | 日次傾向、mentor-briefings、learner-profile.md、Memory.mdを置く | main Agent | learner-profile.mdとMemory.mdは必要時に編集可 |
| .codex/config.toml | 実際の設定値 | main Agentまたは学習者 | はい |
| .codex/config.defaults.toml | 設定チェック定義 | main Agentまたは保守者 | 原則いいえ |
| .codex/skills/ | Skill本文 | main Agentまたは保守者 | 原則いいえ |
| .codex/agents/mentor/ | mentor Agentの責務定義と専用MEMORYを置く | main Agent | 原則いいえ |

## 日次処理の役割

日次処理は、状態ファイルではなく成果物ファイルの存在で処理済みかどうかを判断する。

主に次の内容を扱う。

| 場所 | 役割 |
| --- | --- |
| `.codex/hooks.json` | ユーザー入力時に日次処理scriptとinbox/outbox確認scriptを呼び出す |
| `.codex/internal/scripts/daily_rollup_on_prompt.rb` | 前日のLearning Caseから日次学習傾向を作り、当日のmentor-briefingsがなければ作る |
| `.codex/internal/scripts/inbox_status_on_prompt.rb` | Learning Case本体からinbox/outboxリンク集を再生成し、未完了テーマがあれば一言だけ通知する |
| `notebook/daily-learning-profiles/YYYY-MM-DD.md` | 前日のLearning Caseから作成した日次学習傾向 |
| `notebook/mentor-briefings/YYYY-MM-DD.md` | その日の学習開始時にmentorが読む学習前メモ |

学習者に見せる記録は `learning-cases/`、確定学習ログは `learning-logs/`、学習傾向や苦手は `notebook/` に保存する。
日次処理の二重作成防止は、daily-learning-profilesとmentor-briefingsの各成果物ファイルが存在するかどうかで判断する。

## inbox/outbox索引の役割

inbox/outboxは、Learning Case本体ではなく、自動生成されるリンク集である。

| 場所 | 役割 |
| --- | --- |
| `learning-cases/YYYY-MM-DD.md` | Learning Caseの正本 |
| `learning-cases/inbox/*.md` | `status: in_progress` のLearning Caseへの分野別リンク集 |
| `learning-cases/outbox/*.md` | `status: completed` のLearning Caseへの分野別リンク集 |

`learning-logs/` は確定学習ログ本体を直下に置く場所であり、`learning-logs/inbox/` と `learning-logs/outbox/` は作らない。
確定学習ログのファイル名は `YYYY-MM-DD-NNN-日本語件名.md` を基本にする。
リンク集はUserPromptSubmit hookで再生成されるため、直接編集しない。

## `.codex/agents/mentor/` の役割

`.codex/agents/mentor/` は、mentorだけを独立Agentとして扱うための場所である。

| 場所 | 役割 |
| --- | --- |
| `.codex/agents/mentor/AGENT.md` | mentor Agentの責務、入力、出力、保存権限を説明する |
| `.codex/agents/mentor/MEMORY.md` | learning-casesとlearning-logsから抽出した苦手分析ログを保存する |

mentor専用MEMORYは、`notebook/Memory.md` とは役割が違う。
`.codex/agents/mentor/MEMORY.md` は苦手分析専用、`notebook/Memory.md` は質問傾向や学習者との関わり方を保存する場所として扱う。

## 配布用テンプレートの初期状態

`ProgrammingStudyAiAgent` を他の人がコピーして使い始めるための初期テンプレートとして扱う場合、Agent本体、Skill、設定、README、設計書、保守用検証ファイルを残す。

一方で、次のような個人の学習内容や進行状態は配布用テンプレートに残さない。

- `learning-cases/*.md`
- `learning-logs/*.md`
- `notebook/daily-learning-profiles/*.md`
- `notebook/mentor-briefings/*.md`
- `notebook/learner-profile.md` 内の具体的な苦手傾向
- `notebook/Memory.md` 内の具体的な質問傾向
- `.codex/agents/mentor/MEMORY.md` 内の具体的な苦手分析ログ

配布用テンプレートを更新するときは、学習者個人のログを同期しない。
hook、script、分類ガード、Skill、設計書、内部検証ハーネスなど、Agentの仕組みに関する変更だけを反映する。

## 要件定義と保守ガイド

`docs/RequirementsDefinition.md` は、ProgrammingAIの課題意識、目的、満たすべき要件を確認する文書である。
保守時の全体接続、確認順序、判断表、検証方法は `docs/MAINTAINER_GUIDE.md` にまとめる。
`.codex/internal/validation/ProgrammingAIAgent.rb` は、設定値と保存済み分類ラベルの最小整合性を確認する補助として扱う。
