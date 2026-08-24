# technical_area_aliases 形式Error

## エラーの内容

`technical_area_aliases` の要素に `from` と `to` が揃っていない。

## 影響を受ける処理

- 技術領域の読み替えを使う分析だけ止める。

## 続行する処理

- 通常の質問回答
- 学習ターム作成
- 学習ログ作成

## 修正案

```toml
[[technical_area_aliases]]
from = "Validation"
to = "FormRequest"
```

## 判定

PASS
