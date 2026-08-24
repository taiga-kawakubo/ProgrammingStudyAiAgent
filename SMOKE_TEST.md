# SMOKE_TEST

## 最小フロー

```md
質問
→ 分類
→ 回答
→ 理解確認
→ ターム境界判定または明示的な要約依頼
→ ログ候補
→ 保存許可
→ ローカル学習ログ生成
```

## 実施ルール

1. 1ケースずつ実行する。
2. 期待値と実出力を比較する。
3. ズレた場合は、原因をAgent定義、Skill定義、入力条件、期待値に分ける。
4. Agent定義またはSkill定義を修正する。
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
- learning-term-manager: 参照範囲確認が必要なため、まだターム作成しない
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

### 005 学習タームを作成しない入力

```md
入力:
configの参照範囲設定を変えたいです。

期待値:
- learning-term-manager: create_term=false
- 理由: 設定変更であり学習タームではない
```

### 006 ログ化フロー

```md
入力:
学習者が理解確認に答えた場合、ターム境界候補として扱う。

期待値:
- learning-term-manager: term_boundary_candidate=true, awaiting=log_decision
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
- awaiting: save_permission
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
Route / Controller / Blade の流れで2回つまずいた確定学習ログがある。

期待値:
- mentor Agent: `.codex/agents/mentor/MEMORY.md` に構造理解の苦手候補としてまとめる
- mentor: 最近の学習傾向で苦手を表示する
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
- `.codex/agents/mentor/MEMORY.md` に、日付、分類、つまずき、技術領域、苦手種類、確信度、出現回数、根拠ログが保存される
- 同じ苦手は重複追記ではなく、出現回数と根拠ログとしてまとまる
```

### 012 日付変更後の初回学習質問

```md
入力:
日付が変わった後、最初のプログラミング学習質問が来る。

期待値:
- 前回タームが確認待ちでない場合、mentor分析が走る
- 回答 payload にmentorの最近の学習傾向、復習、確認ポイントが含まれる
- `.codex/state/mentor-session.toml` に当日のmentor実行状態が残る
- 前回タームがログ化確認待ちの場合は、mentorより先に確認待ちを解消する
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
- mentor Agentが、苦手傾向を根拠付きで判定し、必要なものだけmentor表示へ渡せる。

## 不合格時

期待値と実出力がずれた場合は、該当するSkillへ戻る。
同じダミー入力で再検証し、合格するまで次へ進まない。

## 検証履歴

- [2026-08-06-run-001.md](smoke-tests/2026-08-06-run-001.md): 7ケースPASS。検証中に見つけた小さな不整合を修正済み。
- [2026-08-06-save-flow-run-001.md](smoke-tests/2026-08-06-save-flow-run-001.md): サンプル保存フローPASS。learning-cases、learning-logs、notebook、current-term.tomlの生成を確認済み。
- [2026-08-06-additional-flow-run-001.md](smoke-tests/2026-08-06-additional-flow-run-001.md): 追加保存フローPASS。ログ化しない場合の軽量メモ、2件目の自動採番、paused-terms.tomlによる中断状態を確認済み。
- [2026-08-06-resume-flow-run-001.md](smoke-tests/2026-08-06-resume-flow-run-001.md): paused状態からの再開PASS。current-termをunderstanding_checkへ戻す流れを確認済み。
- [2026-08-06-retention-alias-run-001.md](smoke-tests/2026-08-06-retention-alias-run-001.md): 保持日数とtechnical_area_aliases形式Error PASS。古い日次ファイル削除と読み替え分析停止を確認済み。
- [2026-08-06-all-checks-run-001.md](smoke-tests/2026-08-06-all-checks-run-001.md): 保存フロー系の一括検証PASS。
