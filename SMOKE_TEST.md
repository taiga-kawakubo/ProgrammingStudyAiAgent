# SMOKE_TEST

この文書は、ProgrammingAIの要件、AGENTS.md、Skill定義が、代表的な学習シナリオに対して期待どおり読めるかを確認するための手動チェックリストである。
Rubyハーネスは保存フローを再現せず、設定値と保存済み分類ラベルの最小整合性だけを確認する。

## 最小フロー

```md
質問
→ UserPromptSubmit hook
→ daily_rollup_on_prompt.rbによる日次成果物確認
→ inbox_status_on_prompt.rbによるinbox/outbox索引確認
→ 分類
→ Learning Case一次記録
→ 回答
→ 理解確認
→ Learning Case状態更新
→ 必要な場合だけログ化確認または明示的な要約依頼
→ ログ候補
→ 保存許可
→ ローカル学習ログ生成
```

## 実施ルール

1. 1ケースずつ実行する。
2. 期待値と実出力を比較する。
3. ズレた場合は、原因を要件、Agent定義、Skill定義、入力条件、期待値に分ける。
4. 要件、Agent定義、またはSkill定義を修正する。
5. 同じダミー入力で再検証する。
6. 合格するまで次のケースへ進まない。
7. 同じ原因で3回連続して失敗した場合は、学習者へ重要判断として確認する。

## ダミー検証ケース

### 001 feature分類と回答

```md
入力:
ログイン機能でRoute、Controller、Bladeがどうつながっているか分かりません。

期待値:
- classifier: feature
- scope-reader: 参照範囲がないため、コード閲覧前に確認が必要
- feature-answer: 回答する場合は仮定を明示し、全体像、理解ステップ、確認順序を優先する
- learning-log-workflow: 回答未完了のため確定ログは作らず、必要ならLearning Caseに参照範囲確認中として残す
- Learning Case: 戻る価値がある待機が残る場合はstatus: in_progress
```

### 002 unit分類と回答

```md
入力:
$user->books()->create($data) の意味が分かりません。

期待値:
- classifier: unit
- unit-answer: $user、books()、create($data)に分解して説明する
- 回答末尾: 軽い理解確認を1つ入れる
```

### 003 assess分類と回答

```md
入力:
このバリデーションの書き方で問題ありませんか。

期待値:
- classifier: assess
- assess-answer: 現状の確認、評価、改善点、次に見る順番を出す
- 不足情報が大きい場合は回答前に確認する
```

### 004 error分類と回答

```md
入力:
Call to undefined method App\Models\User::books() が出ます。

期待値:
- classifier: error
- error-answer: エラーの意味、発生している場所、原因仮説、確認順序、修正案、検証方法を出す
- 原因を断定しない
```

### 005 Learning Caseに記録しない入力

```md
入力:
configのagent_trace_modeを変えたいです。

期待値:
- learning-log-workflow: learning_case_record_required=false
- 理由: 設定変更であり、プログラミング学習質問ではない
```

### 006 ログ化フロー

```md
入力:
学習者が理解確認に答えた場合、Learning Caseへ理解確認結果を追記する。

期待値:
- learning-log-workflow: Learning Case状態更新案を返す
- 復習価値がある場合だけ、ログ化するかどうかを確認する
- ログ化する場合、学習ログ候補を提示する
- 学習者が明言した内容とAgentの見立てを分ける
- 保存許可まで確定保存しない
```

### 007 明示的な要約依頼

```md
入力:
内容をまとめてほしい。

期待値:
- learning-log-workflow: 学習ログ候補を提示する
- next_user_reply: save_permission
- 保存はまだ行わない
```

### 008 保存拒否

```md
入力:
保存しない。

期待値:
- 確定学習ログを生成しない
- Notion貼り付け用ドラフトを生成しない
- 軽量メモも生成しない
```

### 009 Agent判断の軽量メモ

```md
入力:
同じつまずきが繰り返されたため、Agentが軽量メモを残す価値があると判断した。

期待値:
- source: agent_judgment
- Learning Caseに軽量メモの状態更新を残す
- 確定学習ログは生成しない
```

### 010 苦手傾向判定

```md
入力:
Route / Controller / Blade の流れで2回つまずき、観察パターンとして「複数ファイルの入口、処理、出力を順番に追うところで迷う」が残っている。

期待値:
- profile-memory: 観察パターンを中心に、構造理解の苦手候補としてまとめる
- 関連技術語: Route、Controller、Bladeは補助タグとして扱う
- mentor: 確信度が中以上の場合だけ、最近の学習傾向や復習候補に使う
- 根拠ログリンクは最大3件
- 確信度は通常表示しない
```

### 011 mentor MEMORY更新

```md
入力:
確定学習ログが保存される。

期待値:
- learning-logs直下に確定学習ログが保存される
- mentor Agentがlearning-casesとlearning-logsを分析する
- `.codex/agents/mentor/MEMORY.md` に、日付、分類、つまずき、苦手種類、観察パターン、関連技術語、確信度、出現回数、根拠ログが保存される
- 同じ苦手は観察パターンを中心に、出現回数と根拠ログとしてまとまる
```

### 012 日次学習傾向の観察項目

```md
入力:
日付が変わった後、前日のLearning Caseから日次学習傾向ファイルを作る。

期待値:
- UserPromptSubmit hookが `.codex/internal/scripts/daily_rollup_on_prompt.rb` を呼ぶ
- `notebook/mentor-briefings/YYYY-MM-DD.md` が既にあれば何もしない
- 当日のmentor-briefingsがなければ日次処理を行う
- 質問分類件数を集計する
- 苦手種類候補の集計を出す
- 観察パターンをまとめる
- 関連技術語を補助タグとしてまとめる
- 繰り返し候補を出す
- learner-profile / Memory反映候補を分ける
- `notebook/daily-learning-profiles/前日.md` と `notebook/mentor-briefings/今日.md` が成果物になる
```

### 013 日付変更後の初回学習質問

```md
入力:
日付が変わった後、最初のプログラミング学習質問が来る。

期待値:
- ログ化確認、保存許可、参照範囲確認などの回答待ちでない場合、mentor-briefingsを読む
- 回答 payload にmentorの最近の学習傾向、復習、確認ポイントが含まれる
- 同じ入力に対して、質問分類と回答も続ける
- 処理済み判定は `.codex/state` ではなく `notebook/mentor-briefings/YYYY-MM-DD.md` の存在で行う
- ログ化確認待ちの場合は、mentorより先に確認待ちを解消する
```

### 014 Learning Case status

```md
入力:
プログラミング学習質問がLearning Caseに一次記録される。

期待値:
- 1件ごとに `## YYYY-MM-DD-NNN 学習テーマ` の見出しがある
- case_id: YYYY-MM-DD-NNN がある
- status: in_progress または completed のどちらかだけを使う
- main_topic が1つある
- related_terms は複数でもよい
- next_action がある場合、後で戻る時の確認ポイントとして読める
```

### 015 inbox/outboxリンク集

```md
入力:
Learning Caseに status: in_progress と status: completed の記録がある。

期待値:
- UserPromptSubmit hookが `.codex/internal/scripts/inbox_status_on_prompt.rb` を呼ぶ
- `learning-cases/inbox/*.md` に in_progress のリンクが作られる
- `learning-cases/outbox/*.md` に completed のリンクが作られる
- Learning Case本体は `learning-cases/YYYY-MM-DD.md` から移動しない
- リンク集は main_topic ごとに分かれる
```

### 016 learning-logs outbox

```md
入力:
確定学習ログが `learning-logs/YYYY-MM-DD-NNN-topic.md` にある。

期待値:
- `learning-logs/outbox/*.md` に確定ログへのリンクが作られる
- `learning-logs/inbox/` は作らない
- 確定学習ログは基本的に completed として扱う
```

## 合格条件

- classifierが分類、分類理由、確信度、不足情報、確認要否を返す。
- 質問分類は `feature`、`unit`、`assess`、`error` の4つだけを使い、`summary` や `test` を分類として出さない。
- 回答サブAgentが分類に合うテンプレートで回答する。
- 回答の最後に理解確認が1つある。
- learning-log-workflowが、保存許可なしに確定保存しない。
- 明示的な要約依頼でログ候補だけを作る。
- 保存拒否時に軽量メモを残さない。
- 確定後にlearning-logs直下へ生成候補を作れる。
- UserPromptSubmit hookの日次処理が成果物ファイルの存在で二重実行を避ける。
- UserPromptSubmit hookがinbox/outboxリンク集を再生成し、in_progressがあれば短く通知する。
- Learning Caseのstatusは `in_progress` または `completed` だけを使う。
- `learning-logs/inbox/` を作らない。
- mentorが当日のmentor-briefingsを読み、初回学習質問ではmentor表示後に回答へ続ける。
- profile-memoryとmentor Agentが、観察パターンを中心に苦手傾向を根拠付きで判定し、必要なものだけmentor表示へ渡せる。

## 不合格時

期待値と実出力がずれた場合は、まず `docs/MAINTAINER_GUIDE.md` の判断表で該当する責務を確認し、次に該当するSkillへ戻る。
同じダミー入力で再検証し、合格するまで次へ進まない。

## 旧検証履歴

旧Rubyハーネス時代の検証ログは、現行構成と混同しやすいため削除済み。
現在の検証仕様は、この `SMOKE_TEST.md` を正とする。

## 最小チェッカー

設定値と保存済み分類ラベルの確認は次で行う。

```sh
ruby .codex/internal/validation/ProgrammingAIAgent.rb test
```
