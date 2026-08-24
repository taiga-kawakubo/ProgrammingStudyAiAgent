---
name: learning-term-manager
description: Manage learning term creation, active term state, status transitions, and no-create decisions for ProgrammingAI.
---

# 目的

学習者の入力が新しい学習タームを作成すべき内容かを判断し、作成する場合は日付別Learning Case、自動採番、内部状態、current-term.tomlの更新案をmain Agentへ返す。

# 入力

- 学習者の入力本文
- classifierの分類結果
- scope-readerの参照範囲確認結果
- 現在のcurrent-term.toml
- 現在のmetadata.toml
- config-guardの設定確認結果

# 出力

```md
input_intent: learning_question / management / mentor_command / config / casual / log_request / log_revision / save_permission / save_decline / understanding_answer / resume_choice
create_term: true / false
reason: 判断理由
case_path_candidate:
term_state_path_candidate:
metadata_update_candidate:
current_term_update_candidate:
status:
awaiting:
need_user_confirmation: true / false
```

# 処理手順

1. 入力意図を判定する。
2. 進行中タームのawaitingが `none` 以外の場合は、まず待っている返答に該当するか確認する。
3. 待っている返答と違う内容の場合は、現在のタームを自動終了せず、resume_choice、新規質問候補、ログ保存判断のいずれかとして扱う。
4. 新しい学習質問で、分類と参照範囲が回答可能な状態ならターム作成候補を返す。
5. `learning-cases/YYYY-MM-DD.md` の形式で、日付ごとのLearning Case保存場所を決める。
6. 内部状態は `.codex/state/terms/YYYY-MM-DD/NNN-topic/` に置く。
7. 同一日付内の既存番号を確認し、次の番号を自動採番する。
8. metadata.tomlには、分類、技術領域、参照範囲、状態、awaiting、作成時刻、根拠、case_pathを記録する更新案を返す。
9. current-term.tomlには、現在アクティブな学習タームへのポインタ更新案を返す。
10. 参照範囲が未確定で回答前確認が必要な場合も、プログラミング学習質問であればLearning Caseに `awaiting_scope` として残す。
11. 理解確認への返答は、ターム境界判定の材料として扱う。
12. 新しい学習質問に移った場合も、必要ならターム境界候補として扱う。
13. 内容の要約依頼は新しい学習タームを作らず、既存タームのログ候補作成へ渡す。
14. ターム状態は、学習の進行に合わせてmain Agentへ更新案として返す。
15. ファイル更新はmain Agentが実行する。

# 作成しないケース

次の場合は、学習タームを作成しない。

- 雑談、挨拶、感想だけの入力
- Agent設定、config、Skill、README、要件定義の相談
- メンター表示、学習開始、復習回答だけの入力
- 既存ログ候補の作成、修正、保存可否、修正完了の返答
- 理解確認への回答
- 学習者が明示した範囲外を見ないと回答できない入力
- 同じ学習ターム内の追質問として扱うべき入力

# 状態

metadata.tomlは各学習タームごとの管理台帳として扱う。
current-term.tomlは現在アクティブな学習タームを示すポインタとして扱う。

使用する状態は次の通り。

- created
- answer_created
- understanding_check
- log_decision
- log_draft_created
- log_confirming
- log_saved
- log_discarded
- light_memo_saved
- log_saved
- paused
- closed

# awaiting

使用するawaitingは次の通り。

- none
- scope_confirmation
- user_clarification
- understanding_answer
- log_decision
- log_revision
- save_permission
- resume_choice

# 禁止事項

- 学習質問ではない入力でタームを作成しない。
- 想定外の返答だけで進行中タームをclosedにしない。
- 学習者が明示していない参照範囲を補ってタームを作成しない。
- metadata.tomlまたはcurrent-term.tomlを直接更新しない。
- 過去の確定学習ログを書き換えない。

# メインAgentへ返す管理情報

- ターム作成の可否
- 作成しない理由
- Learning Case保存先候補
- 内部状態保存先候補
- metadata.toml更新案
- current-term.toml更新案
- status更新案
- awaiting更新案
- 学習者へ確認すべき内容

# ダミー検証

```md
1. 「ログイン機能でRouteからControllerまでの流れが分かりません」
前提: classifier=feature, scope_reader=allowed
期待値: create_term=true, learning-cases/YYYY-MM-DD.md と .codex/state/terms/YYYY-MM-DD/001-login-flow/ を候補にする。

2. 「こんにちは」
期待値: create_term=false, reason=雑談であり学習タームではない。

3. 「configの参照範囲設定を変えたいです」
期待値: create_term=false, reason=設定変更であり学習タームではない。

4. awaiting=log_decision の状態で「別の質問ですが、fetchが分かりません」
期待値: 進行中タームを自動終了せず、新規質問候補またはresume_choiceを返す。

5. 「このviewファイルの処理を見てください」だが参照範囲が曖昧
期待値: create_term=true, learning-cases/YYYY-MM-DD.md に awaiting_scope として記録する。

6. 既存タームで「内容をまとめてほしい」
期待値: create_term=false, input_intent=log_request。
```

# 合格条件

5件すべてで、作成するケースと作成しないケースを区別し、metadata.tomlとcurrent-term.tomlの役割に沿った更新案を返せる。

# 不合格時の修正方針

期待値と実出力がずれた場合は、入力意図、作成しないケース、awaiting判定、状態遷移、採番ルールのいずれかを修正し、同じダミー入力で再検証する。
合格するまで次のSkillへ進まない。
