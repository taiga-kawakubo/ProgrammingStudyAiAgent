---
name: learning-log-workflow
description: Manage log/no-log recommendation, learner revision, confirmed local learning logs, and Learning Case status updates.
---

# 目的

学習タームの区切り候補、明示的な要約依頼、Agent判断による軽量メモの3つを扱い、学習者の保存許可を確認したうえで、ローカル保存用の確定学習ログとLearning Caseの状態更新案をmain Agentへ返す。

# 入力

- 学習ターム内の質問
- 回答本文
- 理解確認への返答
- 新しい学習質問によるターム境界候補
- ユーザーの「内容をまとめてほしい」という明示依頼
- classifierの分類結果
- metadata.toml
- 学習者のログ化可否
- 学習者の修正内容

# 出力

```md
term_boundary_candidate: true / false
log_recommendation: log / no_log
log_trigger: term_boundary / explicit_summary_request / agent_judgment
reason: 推奨理由
log_draft:
revision_required: true / false
save_ready: true / false
save_permission: pending / granted / declined / not_requested
light_memo_status: saved / none
confirmed_log_candidate:
learning_case_update_candidate:
metadata_update_candidate:
status:
```

# 処理手順

1. 次のいずれかをログ判定の契機として扱う。
   - ターム境界候補: 理解確認への返答や、新しい学習質問への移行から判定する。
   - 明示的な要約依頼: 「内容をまとめてほしい」などの依頼を受ける。
   - Agent判断: 繰り返しのつまずきなど、軽量メモを残す価値があると判断する。
2. ターム境界候補では、ログ化するかどうかを学習者へ確認する。
3. 明示的な要約依頼では、まず学習ログ候補を作成し、その後に保存許可を確認する。
4. ログ候補の作成だけでは、確定学習ログを保存しない。
5. 学習者が保存を許可した場合だけ、確定学習ログを生成する。
6. 学習者が保存しないと答えた場合、確定学習ログと軽量メモのどちらも保存しない。
7. ログ化しない判断を選んだ場合は、学習内容が残す価値を持つときだけ軽量メモを作成する。
8. Agent判断の軽量メモは、繰り返しのつまずき、明確な進展、重要な未解決事項などに限定する。
9. 回答がない場合は、設定に従い絶対にストップするか、Agent判断で進めるかをmain Agentへ返す。
10. 学習ログ候補では、学習者が明言した内容とAgentの見立てを分ける。
11. 学習者はchatで修正できる。
12. 細かな修正は直接ファイル編集で行える。
13. 学習者が「修正完了」と伝えたら、保存許可を確認する。
14. 保存処理はmain Agentが実行する。

# 保存先ガード

Learning Case、確定学習ログ、日次学習傾向、learner-profile、Memoryは、必ずこのProjectフォルダ内へ保存する。

```md
learning-cases/YYYY-MM-DD.md
learning-logs/YYYY-MM-DD-NNN-topic.md
notebook/daily-learning-profiles/YYYY-MM-DD.md
notebook/learner-profile.md
notebook/Memory.md
```

`/Users/taiga/.codex/memories/`、`.codex/memories/`、`extensions/ad_hoc/notes/` は保存先にしない。
これらはCodex全体の補助メモリであり、ProgrammingAIの学習ケース、確定学習ログ、日次学習傾向、Memoryの保存先ではない。

main AgentがProject外へ保存しようとしている場合は、保存処理を止め、Project内の保存先へ切り替える。

# 学習ログの型

`# 質問分類` には、必ず `feature`、`unit`、`assess`、`error` のいずれかを書く。
`summary` は `log_trigger: explicit_summary_request` として扱い、質問分類には書かない。
`test` はテストコードに関するテーマや技術領域として扱い、質問分類には書かない。

```md
# 学習テーマ

# 質問分類

# 質問した内容

# つまずきの中核

# 学習前の理解

# 学んだ内容

# 処理またはコードの流れ

# 確認したこと

# 次に同じ問題が出たら見る順番

# 他でも使える考え方

# 未解決事項

# 次に学習すること
```

# 修正しやすく分ける項目

学習ログ候補を提示するときは、次を分ける。

- 学習者が明言した内容
- Agentの見立て
- 苦手傾向の候補
- 理解度候補
- 未解決事項候補
- 次に学習すること候補

# 軽量メモを作成するケース

次の場合は、確定学習ログを作らず、必要なら軽量メモ候補を返す。

- 雑談、設定相談、Agent設計相談だけで終わった場合
- 学習内容がほとんど増えていない場合
- 参照範囲が未確定で、回答が完了していない場合
- 回答前確認で止まっている場合
- 同じ学習タームの途中で、まだ理解確認が終わっていない場合
- 同じつまずきが繰り返され、日次傾向として残す価値がある場合

# 保存しないケース

学習者がログ候補の保存を明示的に拒否した場合は、確定学習ログと軽量メモを保存しない。Learning Caseには保存拒否の状態更新だけを残す。

# 禁止事項

- 学習者確認なしに確定学習ログを保存しない。
- 「内容をまとめてほしい」だけで保存まで進めない。
- Notionへ直接保存しない。
- Notion貼り付け用ドラフトを生成しない。
- 確定学習ログ、Learning Case、軽量メモ、Memoryを `/Users/taiga/.codex/memories/`、`.codex/memories/`、`extensions/ad_hoc/notes/` に保存しない。
- Agentの推測を学習者の明言として書かない。
- 確定済み学習ログを後から書き換えない。
- ログ化しない判断を、苦手傾向分析の完全除外として扱わない。
- 軽量メモを確定学習ログや学習者の明言として扱わない。

# メインAgentへ返す管理情報

- ログ化提案
- ログ化の契機
- ログ化しない提案
- 学習ログ候補
- 保存許可の確認
- 修正待ち状態
- 保存可能状態
- Learning Case状態更新案
- metadata.toml更新案
- 日次学習傾向ファイルの軽量メモ候補

# ダミー検証

```md
1. feature回答後、理解確認に学習者が答えた
期待値: term_boundary_candidate=true, awaiting=log_decision。

2. 「内容をまとめてほしい」と依頼された
期待値: log_draft_created=true, awaiting=save_permission, save_permission=pending。

3. 「保存して」と返答された
期待値: 確定学習ログを生成し、Learning Caseに状態更新を残す。

4. 「保存しない」と返答された
期待値: 確定学習ログと軽量メモを生成せず、Learning Caseに保存拒否の状態更新を残す。

5. Agentが繰り返しのつまずきを検知した
期待値: source=agent_judgmentの軽量メモだけを作成する。
```

# 合格条件

5件すべてで、3つの契機、候補提示、保存許可、保存拒否、軽量メモの状態を分けて返せる。

# 不合格時の修正方針

期待値と実出力がずれた場合は、区切り判定、ログ化判断、修正反映、保存可能判定、Learning Case状態更新のいずれかを修正し、同じダミー入力で再検証する。
合格するまで次のSkillへ進まない。
