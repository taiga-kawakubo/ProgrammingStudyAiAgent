---
name: profile-memory
description: Maintain learner profile, daily learning trend notes, weakness observations, and long-term learning memory from learning logs.
---

# 目的

Learning Case、確定学習ログ、日次学習傾向ファイルを主な根拠として、学習者の苦手候補、得意、学習スタイル、注意点、learner-profile、Memoryを更新するための候補をmain Agentへ返す。
mentor専用MEMORYやmentor-briefingsの更新判断は、mentor Agentと日次処理scriptの責務として分けて扱う。
苦手候補は技術領域の固定候補ではなく、Learning Caseに残された `観察パターン` の繰り返しを中心に判断する。

# 入力

- learning-cases/YYYY-MM-DD.md
- 確定学習ログ
- 日次学習傾向ファイル
- learner-profile.md
- Memory.md
- 復習結果

# 出力

```md
daily_learning_profile_candidate:
learner_profile_update_candidate:
memory_update_candidate:
weakness_observation_candidate:
weakness_trend_candidate:
strength_update_candidate:
learning_style_update_candidate:
attention_point_update_candidate:
needs_user_confirmation: true / false
reason:
```

# 処理手順

1. Learning Caseを主な根拠として読む。
2. 確定学習ログは、学習者が保存を許可した整理済みログとして補助的に読む。
3. ログ化されなかったプログラミング学習質問も、Learning Case内の状態更新として扱う。
4. 各Learning Caseから、質問分類、つまずき、苦手種類候補、観察パターン、関連技術語、根拠ログを抽出する。
5. 日次学習傾向ファイルでは、質問分類件数、苦手種類候補の集計、観察パターン、関連技術語、繰り返し候補、learner-profile / Memory反映候補をまとめる。
6. 苦手種類候補は `技術知識`、`構造理解`、`思考プロセス` の3種類に分ける。
7. 技術知識と構造理解を優先する。
8. 関連技術語は補助タグとして扱い、関連技術語だけが一致しても同じ苦手とは判断しない。
9. 同じ観察パターンが1回だけ出た場合は、苦手ではなく内部観察として残す。
10. 同じ観察パターンが2回出た場合、または複数回同じ考え方で間違っている場合は苦手候補にする。
11. 同じ観察パターンが3回以上出た場合、または複数日にまたがって明確に出た場合は、苦手傾向候補にする。
12. 学習者が苦手見立てを肯定した場合だけ、learner-profile.mdへの長期反映候補にする。
13. 学習者が見立てを否定または修正した場合は、古い見立てを弱めるか表現を修正する。
14. 確信度 `中` 以上の候補だけを、learner-profileやMemoryへの反映候補として優先する。
15. 確信度の値そのものは通常表示しない。
16. 確信度 `低` は内部観察として残し、learner-profileへの長期反映候補にはしない。
17. 「最近の学習傾向」に使えそうな内容は、mentor Agentへ渡せる観察要約としてmain Agentに返す。
18. 軽い内容はAgent判断で仮反映候補にする。
19. 苦手傾向など重要な内容は確認必須にする。
20. 日次処理scriptが作った日次学習傾向ファイルは入力として読む。
21. mentor-briefingsの作成、mentor専用MEMORYの更新、学習前表示の作成はこのSkillの責務にしない。
22. main Agentの通常会話では、必要に応じてlearner-profile / Memory反映候補を確認する。

# learner-profile.mdに持つ内容

- 苦手傾向
- 苦手の種類
- 観察パターン
- 関連技術語
- 得意
- 学習スタイル
- 注意点
- 学習者が修正した見立て
- 復習で優先する内容

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
- 関連技術語が同じという理由だけで苦手をまとめない。
- 学習者の修正内容を無視して古い見立てを優先しない。

# メインAgentへ返す管理情報

- 日次学習傾向ファイル更新案
- learner-profile.md更新案
- Memory.md更新案
- 苦手傾向更新案
- 得意更新案
- 学習スタイル更新案
- 注意点更新案
- mentor Agentへ渡す観察要約
- 苦手種類候補の集計
- 観察パターン
- 関連技術語
- 繰り返し候補

# ダミー検証

```md
1. Route / Controller / Blade の流れで2回つまずいたログがある
期待値: 観察パターン「複数ファイルの入口、処理、出力を順番に追うところで迷う」を中心に、構造理解の苦手候補としてまとめる。

2. fetchの意味が1回だけ分からなかったログがある
期待値: 苦手とは断定せず、内部観察または復習候補に留める。

3. Routeという関連技術語だけが2回出ているが、観察パターンが違うログがある
期待値: Routeが苦手とはまとめず、別々の観察として扱う。

4. 同じ観察パターンが3回以上、または複数日にまたがって出ている
期待値: 苦手傾向候補にするが、learner-profile反映前に確認を求める。

5. 学習者が苦手見立てを否定または修正した
期待値: 古い見立てを弱めるか、学習者の言葉に合わせて表現を修正する。
```

# 合格条件

5件すべてで、苦手種類候補、観察パターン、関連技術語、確信度、根拠、更新確認の要否を分けて返せる。

# 不合格時の修正方針

期待値と実出力がずれた場合は、苦手判定、近い苦手のまとめ方、観察パターン、関連技術語、確信度、確認タイミングのいずれかを修正し、同じダミー入力で再検証する。
合格するまで次のSkillへ進まない。
