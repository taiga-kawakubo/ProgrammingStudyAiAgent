---
name: config-defaults-provider
description: Provide default config.toml and config.defaults.toml template content for setup, recovery, and repair proposals.
---

# 目的

`.codex/config.toml` の初期内容と、`.codex/config.defaults.toml` のチェック定義テンプレートを返す。

# 入力

- なし
- または、復旧対象キー
- または、config-guardが修正案を作るために必要な設定キー

# 出力

- テンプレートバージョン
- config.tomlテンプレート本文
- config.defaults.tomlテンプレート本文
- 必須キー一覧
- 各キーのデフォルト値
- 各キーの型
- 各キーの許可値または許可範囲
- 作成、追記、復旧時に学習者へ提示する説明

# 処理手順

1. `templates/config.toml` を初期設定テンプレートとして返す。
2. `templates/config.defaults.toml` をチェック定義テンプレートとして返す。
3. 必須キー、型、初期値、許可値、範囲を根拠として返す。
4. ファイルの作成や更新は行わない。

# 禁止事項

- `.codex/config.toml` を直接作成、更新しない。
- `.codex/config.defaults.toml` を直接作成、更新しない。
- 設定の正誤判定を行わない。
- 学習者承認なしに修正を確定しない。

# エラー時の扱い

テンプレートが読めない場合は、設定チェックを正常実行できない重大エラーとしてmain Agentへ返す。
設定に依存する処理は止める。
通常の質問回答は、設定に依存しない範囲で継続してよい。

# ダミー検証

```md
1. config.tomlが存在しない
期待値: config.tomlテンプレートを返す。

2. config.defaults.tomlが壊れている
期待値: config.defaults.toml復旧用テンプレートを返す。

3. 必須キーが不足している
期待値: 該当キーのデフォルト値と説明を返す。
```

# 合格条件

必要なテンプレート本文、必須キー、型、許可値、範囲を返せる。

# 不合格時の修正方針

テンプレート内容、必須キー一覧、型定義、許可値、許可範囲を修正し、同じダミー入力で再検証する。
合格するまで次のSkillへ進まない。
