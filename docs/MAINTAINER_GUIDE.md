# MAINTAINER_GUIDE

この文書は、ProgrammingAIを保守、検証、改良する人のための内部ガイドです。

学習者が通常利用する場合、この文書を読む必要はありません。
学習者向けの入口は `README.md` です。

## 保守者が確認する順番

1. `README.md`
2. `AGENTS.md`
3. `HARNESS_MAP.md`
4. `PROJECT_STRUCTURE.md`
5. `SMOKE_TEST.md`
6. `docs/ProgrammingAI_requirements_development-ready_2026-08-06.md`

## 内部検証用ファイル

`.codex/internal/validation/ProgrammingAIAgent.rb` は、Projectの主要な保存フローを検証するための内部ハーネスです。

通常の学習利用では、学習者にこのファイルの実行を求めません。
CodexアプリでProjectフォルダを開き、chatで質問する使い方を優先します。

### Rubyファイルの記述方針

Rubyは日本語の文字列、コメント、識別子を扱えます。
ただし、`.codex/internal/validation/ProgrammingAIAgent.rb` では、クラス名、メソッド名、変数名は英語のままにします。

理由は次の通りです。

- 既存コードと検索しやすさを揃えるため
- エラー表示やテスト失敗箇所を追いやすくするため
- Ruby以外のツールやエディタで文字化けや補完ずれを起こしにくくするため

一方で、学習者へ表示する文言、Markdownの見出し、保守者向けコメントは日本語で書いてよいものとします。
複雑な業務ルールを追加する場合は、英語の処理名を保ちつつ、日本語コメントで意図を補足します。

## `.codex/state/` の役割

`.codex/state/` は、main Agentが学習タームを継続、停止、再開するための内部状態を保存する場所です。
学習者向けの記録や確定ログではありません。

主なファイルは次の通りです。

| 場所 | 役割 |
| --- | --- |
| `.codex/state/current-term.toml` | 現在の学習ターム、分類、状態、待機中の返答を管理する |
| `.codex/state/paused-terms.toml` | 中断中の学習タームを管理する |
| `.codex/state/daily-profile-rollover.toml` | 日付変更後の日次学習傾向作成が二重に走らないようにする |
| `.codex/state/terms/` | タームごとの質問、参照内容、回答下書き、ログ下書き、metadataを保存する |

保守時は、次の区別を守ります。

- `learning-cases/`: 日付ごとの一次学習記録
- `learning-logs/`: 学習者が確認した確定学習ログ
- `notebook/`: learner-profile、Memory、日次学習傾向
- `.codex/state/`: Agent内部の進行状態

`.codex/state/` を削除すると、現在の学習ターム、ログ化待ち、日次学習傾向の処理済み状態が分からなくなる可能性があります。
リセットが必要な場合は、学習ログ本体とは分けて扱い、現在のターム状態を確認してから行います。

## 原本の取り扱い

`ProgrammingAI_v2 原本` は、他の人がコピーして使い始めるための初期テンプレートです。
原本には、Agent本体、Skill、設定、README、設計書、保守用検証ファイルだけを残します。

次の個人データは原本へ同期しません。

- `learning-cases/*.md`
- `learning-logs/*.md`
- `notebook/daily-learning-profiles/*.md`
- `notebook/learner-profile.md` 内の具体的な苦手傾向
- `notebook/Memory.md` 内の具体的な質問傾向
- `.codex/agents/mentor/MEMORY.md` 内の具体的な苦手分析ログ
- `.codex/state/terms/`
- `.codex/state/current-term.toml` の進行中ターム

原本を更新する場合は、まず実装、Skill、設定、ドキュメントだけを同期対象にし、学習者の学習内容が混ざっていないか確認します。

## mentor Agent

mentorだけは、独立Agentとして `.codex/agents/mentor/` に置きます。

| 場所 | 役割 |
| --- | --- |
| `.codex/agents/mentor/AGENT.md` | mentor Agentの責務と保存権限を説明する |
| `.codex/agents/mentor/MEMORY.md` | learning-casesとlearning-logsから抽出した苦手分析ログを保存する |

mentor Agentは、learning-casesとlearning-logsから次の項目を抽出します。

- 日付
- 分類
- つまずき
- 技術領域
- 苦手種類
- 確信度
- 出現回数
- 根拠ログ

分類は `feature`、`unit`、`assess`、`error` の4つだけです。
`summary` は明示的な要約依頼やログ化契機、`test` はテストコードに関する技術領域として扱い、質問分類やmentor MEMORYの分類値には使いません。

main Agentは、次のタイミングでmentor分析を呼び出します。

- 確定学習ログ保存時
- `学習開始` 入力時
- 日付が変わった後の最初のプログラミング学習質問

日付変更後の初回学習質問では、古い `current-term` が残っていても、ログ化確認や保存許可などの回答待ちで停止すべき状態でなければmentor出力を先に返します。
`current-term` があることだけを理由に、日次mentor出力を省略しないでください。

mentor Agentは分析結果を返し、ファイル反映はmain Agentが行います。
通常表示では確信度の値を出さず、確信度 `中` または `高` の苦手を復習と確認ポイントへ優先して使います。

## 検証

Agentの分類、参照範囲、ログ保存、Notion貼り付け用Markdown、苦手傾向、保持日数、設定エラーをまとめて確認する場合は、次を実行します。

```sh
ruby .codex/internal/validation/ProgrammingAIAgent.rb test
```

この検証には、Project内の `learning-cases/`、`learning-logs/`、`.codex/agents/mentor/MEMORY.md` に4分類外の質問分類が残っていないかの確認も含まれます。

保存フローまわりの検証ログを作り直す場合は、次を実行します。

```sh
ruby .codex/internal/scripts/run_all_checks.rb
```

合格した場合、次のような結果になります。

```md
PASS: ProgrammingAI agent tests
PASS: all checks generated
```

## 学習者向けに出してはいけないもの

通常の学習者向け回答では、次を出しません。

- 内部検証用ファイルの実行手順
- 保守者向けの検証手順
- Project内部の実装言語名
- 学習者が入力する必要のない専門的な操作

学習者には、Codexアプリで質問すれば使えるAgentとして案内します。

## 改良時の確認

改良後は、次を確認します。

1. `README.md` が学習者向けのままになっている
2. `AGENTS.md` がCodex用の運用指示として読める
3. 学習者向けの入口に内部検証手順が出ていない
4. 参照範囲、ログ化確認、苦手傾向のルールが崩れていない
5. 検証ハーネスがPASSする
