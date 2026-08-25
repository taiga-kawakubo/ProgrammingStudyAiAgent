---
name: learning-log-workflow
description: Manage log/no-log recommendation, learner revision, confirmed local learning logs, and Learning Case status updates.
---

# 目的

プログラミング学習の質問をLearning Caseへ一次記録し、必要に応じて学習ログ候補、保存確認、確定学習ログ、軽量メモの更新案をmain Agentへ返す。

このSkillは、会話途中の専用状態ファイルを管理しない。
日々の学習の事実は `learning-cases/YYYY-MM-DD.md` に残し、確定学習ログは学習者の保存許可がある場合だけ `learning-logs/` に保存する。

# 入力

- 学習者の質問本文
- classifierの分類結果と分類理由
- scope-readerが許可した参照範囲
- 回答本文または回答要点
- 理解確認への返答
- 新しい学習質問への移行
- ユーザーの「内容をまとめてほしい」という明示依頼
- 学習者のログ化可否
- 学習者の修正内容
- 学習者の保存許可または保存拒否
- 既存のLearning Case

# 出力

```md
learning_case_record_required: true / false
learning_case_update_candidate:
case_id:
log_recommendation: log / no_log / not_applicable
log_trigger: learning_question / explicit_summary_request / learner_revision / save_permission / agent_judgment
reason: 推奨理由
log_draft:
revision_required: true / false
save_ready: true / false
save_permission: pending / granted / declined / not_requested
next_user_reply: none / log_decision / learner_revision / save_permission / scope_confirmation
light_memo_candidate:
confirmed_log_candidate:
learning_case_observation_candidate:
status: in_progress / completed
main_topic:
related_terms:
next_action:
```

# 処理手順

1. 入力が、プログラミング学習質問、ログ化依頼、ログ候補の修正、保存許可、保存拒否、設定相談、雑談のどれかを分ける。
2. プログラミング学習質問なら、ログ化可否にかかわらずLearning Caseの更新案を作る。
3. Learning Caseには、case_id、status、main_topic、related_terms、next_action、質問、分類、つまずきの中核、学習内容、苦手種類候補、観察パターン、関連技術語を残す。
4. 回答後や理解確認への返答後、復習価値がありそうな場合だけ、ログ化するかどうかを学習者へ確認する。
5. 「内容をまとめてほしい」などの明示依頼では、まず学習ログ候補を作成し、その後に保存許可を確認する。
6. ログ候補の作成だけでは、確定学習ログを保存しない。
7. 学習者が保存を許可した場合だけ、確定学習ログ候補を返す。
8. 学習者が保存しないと答えた場合、確定学習ログと軽量メモのどちらも作成しない。Learning Caseには保存拒否の状態更新だけを残す。
9. Agent判断の軽量メモは、繰り返しのつまずき、明確な進展、重要な未解決事項などに限定する。
10. 回答待ちの場合は、ログ化確認、ログ候補の修正、保存許可の返答があるまで次へ進まない。
11. 学習ログ候補では、学習者が明言した内容とAgentの見立てを分ける。
12. 学習者はchatで修正できる。
13. ファイル編集による修正は、学習者が明示的に依頼または許可した場合だけmain Agentが扱う。
14. 学習者が「修正完了」と伝えたら、保存許可を確認する。
15. 保存処理はmain Agentが実行する。

# statusの扱い

`status` は `in_progress` と `completed` の2つだけを使う。

`in_progress` にするケース:

- 参照範囲確認待ち。
- 回答前確認待ち。
- 理解確認への返答待ち。
- ログ化する/しないの確認待ち。
- ログ候補の修正待ち。
- 保存する/しないの確認待ち。
- 未解決事項が残り、後で戻る価値がある。

`completed` にするケース:

- 回答が完了し、次に待つユーザー返答がない。
- 学習者が理解した、解決した、保存しない、のいずれかを明示した。
- 保存許可を受けて確定学習ログ候補を返した。
- 未解決事項があっても、その質問サイクルとしては一区切りになった。

`completed` は完全習得ではなく、その質問サイクルが一区切りになったという意味で使う。

# inbox/outbox索引

Learning Case本体は `learning-cases/YYYY-MM-DD.md` に残す。
`learning-cases/inbox/*.md` と `learning-cases/outbox/*.md` は、自動生成されるリンク集として扱う。
このSkillは、リンク集を直接作成しない。
main AgentがLearning Case本体に残した `status` と `main_topic` をもとに、UserPromptSubmit hookのscriptがリンク集を再生成する。

`learning-logs` は確定学習ログであるため、`learning-logs/inbox/` は作らない。
必要な場合だけ、`learning-logs/outbox/*.md` を確定ログのリンク集として扱う。

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
Learning Caseには、既存の質問、つまずき、学習内容を残したうえで、苦手判定に使う一次観察として `苦手種類候補`、`観察パターン`、`関連技術語` を加える。
単発の記録では苦手と断定せず、候補または空欄として扱う。
`関連技術語` は、Laravel、Route、Controller、Blade、Collection、API名、構文名などの補助タグであり、これだけで苦手判定を行わない。

```md
## YYYY-MM-DD-NNN 学習テーマ

case_id: YYYY-MM-DD-NNN
status: in_progress / completed
main_topic:
related_terms:
next_action:

# 質問分類

# 質問した内容

# つまずきの中核

# 苦手種類候補

# 観察パターン

# 関連技術語

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
- 苦手種類候補
- 観察パターン候補
- 関連技術語候補
- 理解度候補
- 未解決事項候補
- 次に学習すること候補

# 軽量メモを作成するケース

次の場合は、確定学習ログを作らず、必要なら軽量メモ候補を返す。

- 雑談、設定相談、Agent設計相談だけで終わった場合
- 学習内容がほとんど増えていない場合
- 参照範囲が未確定で、回答が完了していない場合
- 回答前確認で止まっている場合
- 同じ学習内容の途中で、まだ理解確認が終わっていない場合
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
- Learning Caseへ残す一次観察候補
- inbox/outbox索引に使うstatus
- inbox/outbox索引に使うmain_topic
- 後で戻るためのnext_action

# ダミー検証

```md
1. feature回答後、理解確認に学習者が答えた
期待値: Learning Caseに理解確認結果の更新案を返し、必要ならnext_user_reply=log_decision。

2. 「内容をまとめてほしい」と依頼された
期待値: log_draftを作成し、next_user_reply=save_permission、save_permission=pending。

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
