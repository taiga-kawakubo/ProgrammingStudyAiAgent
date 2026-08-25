# MAINTAINER_GUIDE

この文書は、ProgrammingAIを保守、検証、改良する人のための内部ガイドである。

学習者が通常利用する場合、この文書を読む必要はない。
学習者向けの入口は `README.md` であり、通常回答では内部検証や保守手順を出さない。

## 1. 正本

ProgrammingAIの動作に直接効くルールは、次のファイルに置く。

```md
AGENTS.md
.codex/skills/*/SKILL.md
.codex/agents/mentor/AGENT.md
.codex/config.toml
.codex/hooks.json
```

`docs/RequirementsDefinition.md` は要件定義であり、Codexが毎回自動で読む動作ルールではない。
要件定義を変更した場合は、必要に応じて `AGENTS.md` または対象Skillへ反映する。

## 2. 保守者が確認する順番

通常の改良では、次の順で確認する。

1. `docs/RequirementsDefinition.md`
2. `AGENTS.md`
3. 対象の `.codex/skills/*/SKILL.md`
4. `.codex/agents/mentor/AGENT.md`
5. `.codex/hooks.json`
6. `.codex/internal/scripts/`
7. `.codex/config.toml`
8. `PROJECT_STRUCTURE.md`
9. `SMOKE_TEST.md`

不具合調査では、まず「どの責務の不具合か」を分ける。

| 症状 | 最初に見る場所 |
| --- | --- |
| 分類が違う | `.codex/skills/classifier/SKILL.md` |
| 参照範囲を勝手に読む | `.codex/skills/scope-reader/SKILL.md` と `AGENTS.md` |
| 回答の型が崩れる | 対象の回答Skill |
| Learning Caseへの一次記録が変 | `.codex/skills/learning-log-workflow/SKILL.md` |
| inbox/outboxのリンク集が変 | `.codex/internal/scripts/inbox_status_on_prompt.rb` と `learning-cases/YYYY-MM-DD.md` |
| 未完了メモが出ない | `.codex/hooks.json`、`.codex/internal/scripts/inbox_status_on_prompt.rb`、Learning Caseの `status` |
| ログ保存確認が変 | `.codex/skills/learning-log-workflow/SKILL.md` |
| mentor表示が出ない | `.codex/skills/mentor/SKILL.md` と `.codex/agents/mentor/AGENT.md` |
| 日次学習傾向やmentor-briefingsが作られない | `.codex/hooks.json` と `.codex/internal/scripts/daily_rollup_on_prompt.rb` |
| config keyが読めない | `.codex/skills/config-guard/SKILL.md` と `.codex/config.defaults.toml` |

## 3. 全体接続

ProgrammingAIの入力からログ生成までの接続は、次の流れで確認する。
これはRubyハーネスの処理順ではなく、`AGENTS.md` とSkillが示すAgent運用の接続である。

```md
学習者の質問
→ UserPromptSubmit hook
→ daily_rollup_on_prompt.rb(日次学習傾向 / mentor-briefings準備)
→ inbox_status_on_prompt.rb(inbox/outbox索引更新 / 未完了メモ)
→ main Agent
→ config-guard
→ mentor-briefings確認(必要な場合だけmentor表示)
→ classifier
→ scope-reader
→ learning-log-workflow(Learning Case一次記録)
→ 回答サブAgent(feature / unit / assess / error)
→ 理解確認
→ learning-log-workflow(ログ候補 / 保存許可 / Learning Case状態更新)
→ learning-cases / learning-logs / notebook
→ profile-memory
→ mentor Agent(.codex/agents/mentor/MEMORY.md)
→ mentor
```

見る順番は次の通りである。

1. 質問が学習質問か、管理操作かをmain Agentが見る。
2. UserPromptSubmit hookが、入力のたびに日次処理scriptを呼び出す。
3. scriptは当日のmentor-briefingsがあれば何もせず、なければ前日分のdaily-learning-profilesと当日分のmentor-briefingsを作る。
4. inbox_status_on_prompt.rbがLearning Case本体を読み、inbox/outboxのリンク集を再生成し、未完了があれば一言だけ通知する。
5. config-guardが設定を確認する。
6. `学習開始` または日付変更後の最初の学習質問では、mentorがmentor-briefingsを使って復習と確認ポイントを出す。
7. 最初の学習質問だった場合は、mentor表示後に同じ入力への回答も続ける。
8. classifierが質問分類を返す。
9. scope-readerが参照範囲を確認する。
10. learning-log-workflowが、Learning Caseへの一次記録が必要かを判断する。
11. 分類に応じた回答サブAgentが回答を作る。
12. main Agentが理解確認を行う。
13. learning-log-workflowが、理解確認への返答や新しい学習質問への移行から、ログ化確認が必要かを判断する。
14. 明示的な要約依頼なら、learning-log-workflowがログ候補を作る。
15. 保存許可後だけ確定学習ログを生成する。
16. ログ化しない場合やAgent判断では、Learning Caseに状態更新を残す。
17. 確定学習ログ保存時、mentor Agentがlearning-casesとlearning-logsから苦手候補を分析する。
18. main Agentが `.codex/agents/mentor/MEMORY.md` に分析結果を反映する。

## 4. 日本語判断表

ここは、保守時に「どの判断がどのSkillにあるか」を確認するための表である。
この表自体はAgent本体ではない。

### ConfigGuard

目的は、設定ファイルが読める状態か、設定値が許可された範囲に収まっているかを確認することである。

主な入力:

- `.codex/config.toml`
- `.codex/config.defaults.toml`
- config-defaults-providerのテンプレート

見ること:

- 必須keyが揃っているか。
- 値の型が合っているか。
- 許可値または範囲に収まっているか。
- 不明なkeyを警告に留めるか、処理を止めるか。

基本分岐:

- 正常なら後続処理へ進む。
- 必須key不足は、修正候補を出して影響処理を止める。
- 型や許可値の誤りは、その設定を使う処理だけ止める。
- 不明なkeyは警告にし、通常回答はできるだけ続ける。

現行のconfig key:

| key | 使う場所 | 役割 |
| --- | --- | --- |
| `mentor_start_advice_mode` | `AGENTS.md`、main Agent | mentor表示のタイミング |
| `agent_trace_mode` | `AGENTS.md` | Agent経路の表示粒度 |
| `scope_listing_max_depth` | scope-reader Skill | 明示されたディレクトリの一覧確認の最大深度 |

config keyを増やす判断基準:

- `AGENTS.md`、Skill、hook、scriptのいずれかが、その値に応じて実際に分岐する。
- 変更しても、保存許可、明示範囲参照、秘密情報保護などの安全原則を壊さない。
- `.codex/config.defaults.toml` とRubyチェッカーで型、許可値、範囲を検証できる。
- 固定ルールや単なる分類語彙ではなく、運用上切り替える価値がある。

保存許可、明示範囲参照、秘密情報保護はconfig keyにしない。
これらはProgrammingAIの安全原則として、`AGENTS.md` とSkill本文に固定する。

### Classifier

目的は、学習者の質問を4分類へ分けることである。

分類は次の4つだけを使う。

```md
feature
unit
assess
error
```

判断基準:

- エラー、例外、失敗、動かない、テスト失敗が中心なら `error`。
- 正しいか、十分か、問題ないか、評価してほしいなら `assess`。
- コード一文、関数、メソッド、API、構文の意味が中心なら `unit`。
- 複数ファイル、機能全体、処理やデータの流れが中心なら `feature`。

注意:

- `summary` はログ化契機であり、質問分類にしない。
- `test` は技術領域または文脈であり、質問分類にしない。
- 複数に当てはまる場合は、最初に解くべき問題を優先する。

### ScopeReader

目的は、学習者が明示した範囲だけを参照し、指定外閲覧と秘密情報参照を防ぐことである。

参照できるもの:

- チャットに貼られた内容。
- 具体的に指定されたファイルや行番号。
- `scope_listing_max_depth` の範囲内で確認するディレクトリ一覧。

止めるもの:

- 指定されていない周辺ファイル。
- 曖昧な「このあたり全部」への詳細参照。
- `.env`、秘密鍵、API key、token、password、不要な個人情報。

曖昧な場合は、候補を出して確認する。
候補先の中身は先に読まない。

### LogWorkflow

目的は、プログラミング学習質問をLearning Caseへ一次記録し、学習内容を確定ログにするか、ログ候補に留めるか、保存しないかを管理することである。

Learning Caseへ記録するもの:

- 質問分類。
- 質問した内容。
- つまずきの中核。
- 学習内容。
- 苦手種類候補。
- 観察パターン。
- 関連技術語。

基本フロー:

```md
Learning Caseへの一次記録
-> 回答と理解確認
-> 必要な場合だけログ化する/ログ化しないの確認
-> ログ候補作成
-> 学習者の修正
-> 保存する/保存しないの確認
-> 保存する場合だけ確定ログ化
```

注意:

- `内容をまとめてほしい` はログ候補作成の契機。
- ログ候補を作っただけでは確定保存しない。
- 保存拒否の場合は、確定ログと軽量メモを保存しない。
- 会話全文や不要なコード全文を保存しない。

### MentorMemory

目的は、Learning Caseと確定学習ログから苦手候補を抽出し、mentor Agentが使える形に整理することである。
苦手候補は技術領域の固定候補ではなく、Learning Caseに残る観察パターンの繰り返しを中心に判断する。

主な入力:

- `learning-cases/YYYY-MM-DD.md`
- `learning-logs/YYYY-MM-DD-NNN-topic.md`
- `notebook/daily-learning-profiles/YYYY-MM-DD.md`
- `notebook/mentor-briefings/YYYY-MM-DD.md`
- `.codex/agents/mentor/MEMORY.md`

苦手種類:

```md
技術知識
構造理解
思考プロセス
```

判断基準:

- Learning Caseに `苦手種類候補`、`観察パターン`、`関連技術語` が残っているか。
- 同じ観察パターンが複数回出ているか。
- 関連技術語だけで同じ苦手と断定していないか。
- 1回なら内部観察、2回なら苦手候補、3回以上または複数日にまたがるなら苦手傾向候補として扱っているか。
- learner-profile反映前に、学習者の肯定または修正を確認しているか。
- 確信度 `中` または `高` を通常表示や復習候補に使う。
- 確信度 `低` は内部観察に留める。

## 5. 内部検証用Ruby

`.codex/internal/validation/ProgrammingAIAgent.rb` は、Projectの主要判断を実装する内部ハーネスではない。
現行構成では、設定値と保存済み分類ラベルの最小整合性を確認するチェッカーである。

このRubyは、学習者向け会話では案内しない。
保守者が設定値や保存済み分類ラベルの破損を確認する場合だけ使う。

確認できること:

- `.codex/config.toml` の必須key、型、許可値が壊れていない。
- 保存済みログやmentor MEMORYに4分類外の質問分類が混ざっていない。

確認できないこと:

- 実際の会話品質。
- 保存フローの全自動再現。
- mentorの判断が学習者に合っているか。
- 各Skillの文章が十分に分かりやすいか。

## 6. Rubyファイルの記述方針

Rubyは日本語の文字列、コメント、識別子を扱える。
ただし、`.codex/internal/validation/ProgrammingAIAgent.rb` では、クラス名、メソッド名、変数名は英語のままにする。

理由は次の通りである。

- 既存コードと検索しやすさを揃えるため。
- エラー表示や失敗箇所を追いやすくするため。
- Ruby以外のツールやエディタで補完ずれを起こしにくくするため。

学習者へ表示する文言、Markdownの見出し、保守者向けコメントは日本語でよい。

## 7. 日次hook/scriptの役割

日次処理は、UserPromptSubmit hookとRuby scriptで行う。
状態ファイルではなく、成果物ファイルの存在で処理済みかどうかを判断する。

主な場所:

| 場所 | 役割 |
| --- | --- |
| `.codex/hooks.json` | ユーザー入力時に日次処理scriptを呼び出す |
| `.codex/internal/scripts/daily_rollup_on_prompt.rb` | 当日のmentor-briefingsがなければ、前日のLearning Caseから日次学習傾向とmentor-briefingsを作る |
| `.codex/internal/scripts/inbox_status_on_prompt.rb` | Learning Case本体からinbox/outboxリンク集を再生成し、未完了テーマを短く通知する |
| `notebook/daily-learning-profiles/YYYY-MM-DD.md` | 前日のLearning Caseから作成される日次学習傾向 |
| `notebook/mentor-briefings/YYYY-MM-DD.md` | その日の学習開始時にmentorが読む学習前メモ |

`notebook/mentor-briefings/YYYY-MM-DD.md` が存在する場合、scriptはその日の処理済みと判断して終了する。
再生成したい場合は、対象日のmentor-briefingsを削除してから、scriptを再実行する。

## 8. 保存先の区別

| 場所 | 役割 |
| --- | --- |
| `learning-cases/` | 日付ごとの一次学習記録 |
| `learning-cases/inbox/` | `status: in_progress` のLearning Caseへの分野別リンク集 |
| `learning-cases/outbox/` | `status: completed` のLearning Caseへの分野別リンク集 |
| `learning-logs/` | 学習者が確認した確定学習ログ |
| `learning-logs/outbox/` | 確定学習ログへの分野別リンク集 |
| `notebook/` | daily-learning-profiles、mentor-briefings、learner-profile、Memory |
| `.codex/hooks.json` | Codex hookの登録 |
| `.codex/internal/scripts/` | hookから呼ぶ機械的な補助処理 |
| `.codex/agents/mentor/MEMORY.md` | mentor Agent専用の苦手分析ログ |

ProgrammingAIの学習ログ保存先として、`/Users/taiga/.codex/memories/`、`.codex/memories/`、`extensions/ad_hoc/notes/` を使わない。

`notion-drafts/` は現行構成では使用しない。
`learning-cases/YYYY-MM-DD.md` が正本であり、inbox/outboxは自動生成のリンク集である。
リンク集を直接編集しても、次回のUserPromptSubmit hookで再生成される。
`learning-logs/inbox/` は作らない。

## 9. 原本の取り扱い

`ProgrammingAI_v2 原本` は、他の人がコピーして使い始めるための初期テンプレートである。
原本には、Agent本体、Skill、設定、README、設計書、保守用検証ファイルだけを残す。

次の個人データは原本へ同期しない。

- `learning-cases/*.md`
- `learning-logs/*.md`
- `notebook/daily-learning-profiles/*.md`
- `notebook/mentor-briefings/*.md`
- `notebook/learner-profile.md` 内の具体的な苦手傾向
- `notebook/Memory.md` 内の具体的な質問傾向
- `.codex/agents/mentor/MEMORY.md` 内の具体的な苦手分析ログ

原本を更新する場合は、まずhook、script、実装、Skill、設定、ドキュメントだけを同期対象にし、学習者の学習内容が混ざっていないか確認する。

## 10. mentor Agent

mentorだけは、独立Agentとして `.codex/agents/mentor/` に置く。

| 場所 | 役割 |
| --- | --- |
| `.codex/agents/mentor/AGENT.md` | mentor Agentの責務と保存権限を説明する |
| `.codex/agents/mentor/MEMORY.md` | learning-casesとlearning-logsから抽出した苦手分析ログを保存する |

main Agentは、次のタイミングでmentor分析を呼び出す。

- 確定学習ログ保存時
- `学習開始` 入力時
- 日付が変わった後の最初のプログラミング学習質問

日付変更後の初回入力では、UserPromptSubmit hookのscriptが当日のmentor-briefingsを準備する。
日付変更後の初回学習質問では、ログ化確認、保存許可、参照範囲確認などの回答待ちで停止すべき状態でなければmentor出力を先に返し、その後に同じ質問への回答も続ける。

## 11. 検証

設定値と保存済み分類ラベルを確認する場合は、次を実行する。

```sh
ruby .codex/internal/validation/ProgrammingAIAgent.rb test
```

日次処理scriptの構文を確認する場合は、次を実行する。

```sh
ruby -c .codex/internal/scripts/daily_rollup_on_prompt.rb
ruby -c .codex/internal/scripts/inbox_status_on_prompt.rb
```

合格した場合、次のような結果になる。

```md
PASS: ProgrammingAI config, classification, and status validation
```

この検証は、保存フローを自動生成したり、Learning Caseを作成したりしない。
保存やmentor更新の判断は、`AGENTS.md` とSkill本文を読んで確認する。

手動の代表シナリオ確認は `SMOKE_TEST.md` を使う。

## 12. 旧Rubyハーネスからの変更

以前の構成では、Rubyハーネスが分類、回答、保存、mentor更新を広く再現していた。
現行構成では、その役割を縮小し、Rubyは最小チェッカーだけにする。

削除した旧補助スクリプトは、現行運用では使用しない。
旧Rubyハーネス時代の検証ログは、現行構成と混同しやすいため削除済み。

## 13. 学習者向けに出してはいけないもの

通常の学習者向け回答では、次を出さない。

- 内部検証用ファイルの実行手順
- 保守者向けの検証手順
- Project内部の実装言語名
- 学習者が入力する必要のない専門的な操作

学習者には、Codexアプリで質問すれば使えるAgentとして案内する。

## 14. 改良時の確認

改良後は、次を確認する。

1. `README.md` が学習者向けのままになっている。
2. `AGENTS.md` がCodex用の運用指示として読める。
3. 対象Skillが責務外の処理を持っていない。
4. 学習者向け入口に内部検証手順が出ていない。
5. 参照範囲、ログ化確認、苦手傾向のルールが崩れていない。
6. 最小チェッカーがPASSする。
