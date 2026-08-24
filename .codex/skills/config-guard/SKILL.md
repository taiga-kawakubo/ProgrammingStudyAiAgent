---
name: config-guard
description: Validate config.toml against config.defaults.toml before config-dependent processing.
---

# 目的

`.codex/config.toml` を使用する前に、形式、必須キー、型、許可値、許可範囲を確認し、使える設定と止めるべき処理をmain Agentへ返す。

現行の検証対象keyは次の3つである。

```md
mentor_start_advice_mode
agent_trace_mode
scope_listing_max_depth
```

# 入力

- `.codex/config.toml`
- `.codex/config.defaults.toml`
- config-defaults-providerのテンプレート出力

# 出力

- 設定ファイルを使用できるか
- 形式エラーの有無
- エラーがある設定キー
- 影響を受ける機能
- 通常回答を継続できるか
- 学習者へ提示するエラー内容
- 学習者へ提示する修正案
- 学習者へ提示する警告内容
- 学習者へ提示する警告箇所
- 修正案に使用したデフォルト値の根拠

# 処理手順

1. config.defaults.tomlが読めるか確認する。
2. config.tomlが存在するか確認する。
3. TOMLとして読めるか確認する。
4. 必須キーがあるか確認する。
5. 値の型が正しいか確認する。
6. 許可値または許可範囲内か確認する。
7. 不明なキーは警告として返す。
8. 影響を受ける処理だけを止める。
9. デフォルト値を使った修正案を提示する。
10. 学習者が承認した場合だけmain Agentが修正する。

# 禁止事項

- 学習者承認なしにconfigを修正しない。
- config.defaults.tomlが壊れている状態で設定依存処理を進めない。
- 不明キーだけで通常回答全体を止めない。
- 秘密情報を表示しない。

# エラー時の扱い

config.defaults.tomlが読めない場合は重大エラーとし、設定依存処理を止める。
config.tomlの一部キーだけに問題がある場合は、その設定を使う処理だけ止める。
通常の質問回答は、影響がなければ継続する。

# ダミー検証

```md
1. config.tomlに必須キーがない
期待値: 不足キー、デフォルト値、修正案を返す。

2. scope_listing_max_depth = "two"
期待値: 型エラーとして扱い、該当設定を使う処理を止める。

3. unknown_key = true
期待値: 警告として表示し、通常処理は続ける。
```

# 合格条件

TOML、必須キー、型、許可値、範囲、不明キーを区別して返せる。

# 不合格時の修正方針

検査順序、エラー分類、修正案の出し方を修正し、同じダミー入力で再検証する。
合格するまで次のSkillへ進まない。
