# SMOKE_TEST

この文書は、ProgrammingAIの現行仕様が代表的な学習フローで崩れていないかを確認するための手動チェックリストである。
Rubyチェッカーは会話全体を再現せず、config、保存済み分類ラベル、Learning Case status、保存先の最小整合性だけを確認する。

## 現行仕様の前提

- 質問分類は `feature`、`unit`、`assess`、`error` の4つだけを使う。
- `summary` は要約依頼またはログ化契機、`test` は技術領域として扱い、質問分類にはしない。
- 学習者が明示した参照範囲だけを見る。
- プログラミング学習質問は、ログ化可否にかかわらず `learning-cases/YYYY-MM-DD.md` に一次記録する。
- Learning Caseは `status: in_progress` または `status: completed` を持つ。
- `learning-cases/inbox/` と `learning-cases/outbox/` は、Learning Case正本への自動生成リンク集である。
- 確定学習ログは、保存許可後だけ `learning-logs/YYYY-MM-DD-NNN-日本語件名.md` として直下に保存する。
- `learning-logs/inbox/` と `learning-logs/outbox/` は作らない。
- 日次処理は、UserPromptSubmit hookから呼ばれるscriptが成果物ファイルの存在で二重作成を避ける。

## 最小フロー

```md
学習者の入力
-> UserPromptSubmit hook
-> daily_rollup_on_prompt.rb
-> inbox_status_on_prompt.rb
-> main Agent
-> config-guard
-> mentor表示の要否確認
-> classifier
-> scope-reader
-> learning-log-workflow
-> 回答Skill
-> 理解確認
-> Learning Case状態更新
-> 必要な場合だけログ候補と保存許可
-> 保存許可後だけlearning-logs直下に確定ログ
```

## 実施ルール

1. 1ケースずつ実行する。
2. 期待値と実出力を比較する。
3. ズレた場合は、要件、Agent定義、Skill定義、script、入力条件のどこに原因があるかを分ける。
4. 修正後は同じダミー入力で再検証する。

## 手動スモークケース

### 001 質問分類と回答Skill

```md
入力例:
Route、Controller、Bladeの流れが分かりません。

期待値:
- classifierが `feature`、`unit`、`assess`、`error` のいずれかを返す。
- 上の入力は、複数ファイルの流れが中心なので `feature` になる。
- 回答冒頭に分類と分類理由が短く出る。
- 対応する回答Skillの型で説明される。
- 回答末尾に軽い理解確認が1つある。
```

### 002 参照範囲

```md
入力例:
このControllerの処理を教えてください。

期待値:
- 対象ファイルが明示されていない場合、scope-readerが候補提示または確認を行う。
- 指定されていない周辺ファイルを先に読まない。
- ディレクトリが明示された場合だけ、`scope_listing_max_depth` の範囲で浅い一覧を確認する。
```

### 003 Learning Case一次記録

```md
入力例:
$user->books()->create($data) の意味が分かりません。

期待値:
- `learning-cases/YYYY-MM-DD.md` に一次記録する。
- 1件ごとに `## YYYY-MM-DD-NNN 学習テーマ` の見出しがある。
- `case_id: YYYY-MM-DD-NNN` がある。
- `status: in_progress` または `status: completed` のどちらかだけを使う。
- `main_topic`、`related_terms`、必要なら `next_action` がある。
- 苦手判定用に `苦手種類候補`、`観察パターン`、`関連技術語` を残す。
```

### 004 inbox/outboxリンク集

```md
入力条件:
Learning Caseに `status: in_progress` と `status: completed` の記録がある。

期待値:
- UserPromptSubmit hookが `.codex/internal/scripts/inbox_status_on_prompt.rb` を呼ぶ。
- `learning-cases/inbox/*.md` に `in_progress` のLearning Caseへのリンクが作られる。
- `learning-cases/outbox/*.md` に `completed` のLearning Caseへのリンクが作られる。
- Learning Case本体は `learning-cases/YYYY-MM-DD.md` から移動しない。
- `learning-logs/inbox/` と `learning-logs/outbox/` は作られない。
```

### 005 ログ候補と確定保存

```md
入力例:
内容をまとめてほしい。

期待値:
- learning-log-workflowが学習ログ候補を提示する。
- ログ候補を作っただけでは確定保存しない。
- 保存許可を別に確認する。
- 保存許可後だけ `learning-logs/YYYY-MM-DD-NNN-日本語件名.md` に確定ログを作る。
- 日本語件名は短く、ファイル名に使えない記号を含まない。
```

### 006 保存拒否

```md
入力例:
保存しない。

期待値:
- 確定学習ログを生成しない。
- 軽量メモも生成しない。
- Learning Caseには保存拒否の状態更新だけを残す。
```

### 007 日次処理とmentor表示

```md
入力条件:
日付が変わった後、最初のプログラミング学習質問が来る。

期待値:
- UserPromptSubmit hookが `.codex/internal/scripts/daily_rollup_on_prompt.rb` を呼ぶ。
- 前日のLearning Caseがあり、前日分のdaily-learning-profilesがなければ作成する。
- 当日の `notebook/mentor-briefings/YYYY-MM-DD.md` がなければ作成する。
- 前日のLearning Caseがない場合も、判断材料が少ないことをmentor-briefingsに残す。
- 回答待ちで停止すべき状態がなければ、mentor表示後に同じ質問への回答も続ける。
- 処理済み判定は `.codex/state` ではなく、daily-learning-profilesとmentor-briefingsの存在で行う。
```

### 008 苦手傾向判定

```md
入力条件:
複数のLearning Caseに、似た観察パターンが残っている。

期待値:
- profile-memoryとmentor Agentは、関連技術語だけで苦手を断定しない。
- 観察パターンの繰り返しを中心に、技術知識、構造理解、思考プロセスへ分ける。
- 1回だけなら内部観察、2回なら苦手候補、3回以上または複数日にまたがるなら苦手傾向候補として扱う。
- learner-profileへ長期傾向として反映する前に、学習者の肯定または修正を確認する。
```

### 009 最小チェッカー

```sh
ruby -c .codex/internal/validation/ProgrammingAIAgent.rb
ruby -c .codex/internal/scripts/daily_rollup_on_prompt.rb
ruby -c .codex/internal/scripts/inbox_status_on_prompt.rb
ruby .codex/internal/validation/ProgrammingAIAgent.rb test
```

期待値:

```md
PASS: ProgrammingAI config, classification, status, and log location validation
```

## 合格条件

- 4分類以外の質問分類が出ない。
- 明示されていない参照範囲を読まない。
- Learning Case正本とinbox/outboxリンク集の役割が分かれている。
- `learning-logs/` は確定ログ直下保存だけに使う。
- `learning-logs/inbox/` と `learning-logs/outbox/` を作らない。
- 保存許可なしに確定ログを保存しない。
- mentorは根拠が少ない苦手を断定しない。
- 最小チェッカーがPASSする。
