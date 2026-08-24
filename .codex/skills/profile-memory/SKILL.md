---
name: profile-memory
description: Maintain learner profile, daily learning trend notes, weak area hypotheses, retention, and technical area aliases from learning logs.
---

# 目的

Learning Caseと確定学習ログを主な根拠として、学習者の苦手傾向、得意、学習スタイル、注意点、日次学習傾向、Memoryを更新するための候補をmain Agentへ返す。
苦手分析の集計と復習優先度の判断は、mentor専用MEMORYである `.codex/agents/mentor/MEMORY.md` と役割を分けて扱う。

# 入力

- learning-cases/YYYY-MM-DD.md
- 確定学習ログ
- 日次学習傾向ファイル
- learner-profile.md
- Memory.md
- `.codex/agents/mentor/MEMORY.md`
- technical_area_aliases
- technical_area_custom_candidates
- 復習結果
- 設定値

# 出力

```md
daily_learning_profile_candidate:
learner_profile_update_candidate:
memory_update_candidate:
weakness_update_candidate:
strength_update_candidate:
learning_style_update_candidate:
attention_point_update_candidate:
technical_area_alias_update_candidate:
needs_user_confirmation: true / false
reason:
```

# 処理手順

1. Learning Caseを主な根拠として読む。
2. 確定学習ログは、学習者が保存を許可した整理済みログとして補助的に読む。
3. ログ化されなかったプログラミング学習質問も、Learning Case内の状態更新として扱う。
4. technical_area_aliasesを使い、過去ログを書き換えずに新しい技術領域名へ読み替える。
5. 読み替え設定に形式Errorがある場合は、読み替えを使う分析だけ止め、通常の質問回答は続ける。
6. 新しい技術領域が出た場合は、technical_area_custom_candidatesとして保存候補を返す。
7. 苦手候補を `技術知識`、`構造理解`、`思考プロセス` の3種類に分ける。
8. 技術知識と構造理解を優先する。
9. 同じ苦手が2回以上出た場合、または複数回同じ考え方で間違っている場合は苦手候補にする。
10. 同じ苦手が3回以上出た場合、または複数の根拠ログで同じつまずきが明確な場合は、関連テーマの学習時に回答へ反映する候補にする。
11. 確信度 `中` 以上の候補だけを通常表示の対象にする。
12. 確信度の値そのものは通常表示しない。
13. 確信度 `低` は内部観察として残し、通常表示しない。
14. 苦手候補は、質問分類、技術領域、苦手種類、参照範囲のうち2個以上一致する場合に近い苦手としてまとめる。
15. 4日に1回の「最近の学習傾向」表示時に、苦手のまとめ方や重要なプロフィール更新を確認する。
16. 軽い内容はAgent判断で仮反映候補にする。
17. 苦手傾向など重要な内容は確認必須にする。
18. 日付が変わった後の最初の `学習開始` または最初のプログラミング学習質問で、前日のLearning Caseから日次学習傾向ファイル更新候補を返す。
19. 日次学習傾向ファイルは設定日数を超えたものを削除候補にする。

# learner-profile.mdに持つ内容

- 苦手傾向
- 苦手の種類
- 技術領域
- 得意
- 学習スタイル
- 注意点
- 学習者が修正した見立て
- 復習で優先する内容
- technical_area_aliases
- technical_area_custom_candidates

# Memory.mdに持つ内容

- 質問傾向
- 何度も出る質問
- 確認順序の癖
- 学習者に合う説明の進め方
- learner-profileへ入れる前の長期観察

# 表示ルール

学習者には、通常は確信度を表示しない。
必要な場合だけ、根拠ログリンクや詳細確認で確信度を確認できる形にする。
根拠ログリンクは最大3件までにする。

# 禁止事項

- 確定学習ログを書き換えない。
- 確信度の値そのものを通常表示しない。
- 確信度 `低` の苦手を通常表示の対象にしない。
- 苦手を根拠なしに断定しない。
- learner-profile.mdを直接更新しない。
- technical_area_aliasesの形式Errorを通常回答全体の停止理由にしない。
- 学習者の修正内容を無視して古い見立てを優先しない。

# メインAgentへ返す管理情報

- 日次学習傾向ファイル更新案
- learner-profile.md更新案
- Memory.md更新案
- mentor専用MEMORY更新案
- 苦手傾向更新案
- 得意更新案
- 学習スタイル更新案
- 注意点更新案
- 復習候補
- 技術領域の読み替え結果
- 技術領域候補
- 削除対象の日次学習傾向ファイル候補

# ダミー検証

```md
1. Route / Controller / Blade の流れで2回つまずいたログがある
期待値: 構造理解の苦手候補としてまとめる。

2. fetchの意味が1回だけ分からなかったログがある
期待値: 苦手とは断定せず、内部観察または復習候補に留める。

3. ValidationとFormRequestを同じ内容として読み替えるaliasがある
期待値: 確定ログを書き換えず、分析時だけ読み替える。

4. technical_area_aliasesの形式が壊れている
期待値: 読み替え分析だけ止め、形式Errorと修正案を返す。

5. 同じ技術知識の苦手が3回以上ある
期待値: 関連する学習テーマのときだけ回答へ反映する候補を返す。
```

# 合格条件

5件すべてで、苦手の種類、確信度、根拠、読み替え、更新確認の要否を分けて返せる。

# 不合格時の修正方針

期待値と実出力がずれた場合は、苦手判定、近い苦手のまとめ方、確信度、読み替え、確認タイミングのいずれかを修正し、同じダミー入力で再検証する。
合格するまで次のSkillへ進まない。
