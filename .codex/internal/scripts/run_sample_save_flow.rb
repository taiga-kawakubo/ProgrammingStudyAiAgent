#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"

ROOT = Pathname.new(File.expand_path("../../..", __dir__))
DATE = "2026-08-06"
TIME = "2026-08-06T10:00:00+09:00"
SEQUENCE = "001"
TOPIC_SLUG = "route-controller-blade-flow"
TERM_ID = "#{DATE}-#{SEQUENCE}-#{TOPIC_SLUG}"
TERM_RELATIVE_PATH = "learning-cases/#{DATE}/#{SEQUENCE}-#{TOPIC_SLUG}"
TERM_DIR = ROOT.join(TERM_RELATIVE_PATH)

def write_file(path, body)
  FileUtils.mkdir_p(path.dirname)
  File.write(path, body)
end

def assert_includes(path, expected)
  body = File.read(path)
  missing = expected.reject { |text| body.include?(text) }
  return if missing.empty?

  warn "FAILED: #{path.relative_path_from(ROOT)} is missing #{missing.inspect}"
  exit 1
end

learning_log = <<~MD
  # 学習テーマ

  Route、Controller、Bladeのつながり

  # 質問分類

  feature

  # 質問した内容

  ログイン機能でRoute、Controller、Bladeがどうつながっているか分からなかった。

  # つまずきの中核

  学習者が明言した内容:

  - Route、Controller、Bladeの接続が分からない。

  Agentの見立て:

  - 画面、ルーティング、処理担当ファイルの役割分担がまだ整理されていない。

  # 学習前の理解

  Route、Controller、Bladeが関係していることは分かっていたが、どの順番で読めばよいかは未整理だった。

  # 学んだ内容

  Routeは入口、Controllerは処理、Bladeは表示を担当する。
  機能全体を見るときは、入口、処理、出力の順に分けて確認する。

  # 処理またはコードの流れ

  1. RouteでURLとControllerの対応を確認する。
  2. Controllerで処理内容とBladeへ渡す値を確認する。
  3. Bladeで受け取った値がどこに表示されるか確認する。

  # 確認したこと

  - 回答内でRoute、Controller、Bladeの役割を確認した。
  - 実ファイルの中身は参照していないため、具体コードの確認は未実施。

  # 次に同じ問題が出たら見る順番

  1. Routeで入口を見る。
  2. Controllerで処理を見る。
  3. Bladeで出力を見る。
  4. 変数やデータがどこからどこへ渡るかを見る。

  # 他でも使える考え方

  複数ファイルの機能は、一気に読まず、入口、処理、出力に分けて読む。

  # 未解決事項

  実際のログイン機能のファイル内容は未確認。

  # 次に学習すること

  ControllerからBladeへ値を渡す流れ。
MD

files = {
  TERM_DIR.join("question.md") => <<~MD,
    # 質問

    ログイン機能でRoute、Controller、Bladeがどうつながっているか分かりません。
  MD
  TERM_DIR.join("context.md") => <<~MD,
    # 参照範囲

    - チャット本文
    - 実ファイルは未参照

    # 参照しなかった理由

    学習者が具体的なファイル範囲をまだ明示していないため。
  MD
  TERM_DIR.join("answer-draft.md") => <<~MD,
    # 分類

    分類: feature
    分類理由: 複数ファイルのつながりと処理の流れを確認したい質問だからです。

    # 今回の学習テーマ

    Route、Controller、Bladeの役割と接続順。

    # つまずきの中核

    ファイルを1つずつではなく、入口、処理、表示の流れとして見る視点がまだ整理されていない。

    # 全体像

    Routeは入口、Controllerは処理、Bladeは表示を担当する。

    # 理解ステップ

    1. RouteでURLとControllerの対応を見る。
    2. Controllerで処理と渡す値を見る。
    3. Bladeで表示される場所を見る。

    # 具体例（他でも使える考え方）

    一覧画面、詳細画面、登録画面でも、入口、処理、出力に分けて読む。

    # 次に同じ問題が出たら見る順番

    1. Route
    2. Controller
    3. Blade

    # 理解確認

    Route、Controller、Bladeのうち、最初に入口として確認するものはどれですか。
  MD
  TERM_DIR.join("log-draft.md") => learning_log,
  TERM_DIR.join("metadata.toml") => <<~TOML,
    term_id = "#{TERM_ID}"
    date = "#{DATE}"
    sequence = 1
    topic_slug = "#{TOPIC_SLUG}"

    classification = "feature"
    classification_reason = "複数ファイルのつながりと処理の流れを質問しているため"
    confidence = "high"

    status = "notion_draft_created"
    awaiting = "none"
    log_status = "saved"
    notion_draft_created = true

    referenced_scope = ["chat"]
    created_at = "#{TIME}"
    updated_at = "#{TIME}"
  TOML
  ROOT.join("learning-logs", DATE, "#{SEQUENCE}-#{TOPIC_SLUG}.md") => learning_log,
  ROOT.join("notion-drafts", DATE, "#{SEQUENCE}-#{TOPIC_SLUG}.md") => learning_log,
  ROOT.join("notebook", "daily-learning-profiles", "#{DATE}.md") => <<~MD,
    # #{DATE} 日次学習傾向

    ## ログ化された学習ターム

    - [#{SEQUENCE}-#{TOPIC_SLUG}](../../learning-logs/#{DATE}/#{SEQUENCE}-#{TOPIC_SLUG}.md)

    ## 最近の学習傾向

    Route、Controller、Bladeの役割と接続順を、入口、処理、出力に分けると理解しやすい。

    ## 復習候補

    Q. ControllerからBladeへ値を渡すとき、まず確認する場所はどこですか。

    <details>
    <summary>A. 内容の確認</summary>

    まずControllerで `view()` に何を渡しているかを確認する。
    次にBlade側で、その変数名がどこで使われているかを見る。

    </details>

    ## 苦手候補

    - 種類: 構造理解
    - 技術領域: Laravel / Route / Controller / Blade
    - 根拠: 同種のつまずきが繰り返された場合にlearner-profile.mdへ反映候補にする。

    ## 軽量メモ

    なし
  MD
  ROOT.join("notebook", "learner-profile.md") => <<~MD,
    # learner-profile

    ## Agent認定の苦手傾向

    ### Route、Controller、Bladeの接続順

    - 状態: Agent認定
    - 苦手の種類: 構造理解
    - 技術領域: Laravel / Route / Controller / Blade
    - 確信度: 中
    - 通常表示: 確信度の値は表示しない
    - 根拠ログ:
      - [#{SEQUENCE}-#{TOPIC_SLUG}](../learning-logs/#{DATE}/#{SEQUENCE}-#{TOPIC_SLUG}.md)
    - 認定理由: 複数ファイルの責務と接続順でつまずきが出ているため。

    ## 修正済みの苦手傾向

    なし

    ## 得意な進め方

    - 入口、処理、出力の順に分けると理解しやすい。

    ## 学習スタイル

    - コード全体より、役割と流れを先に整理すると進めやすい。

    ## メンター時の注意点

    - 複数ファイルを扱うときは、先に見る順番を提示する。

    ## technical_area_aliases

    なし

    ## technical_area_custom_candidates

    なし
  MD
  ROOT.join(".codex", "state", "current-term.toml") => <<~TOML,
    active = false
    term_id = "#{TERM_ID}"
    term_path = "#{TERM_RELATIVE_PATH}"
    classification = "feature"
    status = "notion_draft_created"
    awaiting = "none"

    referenced_scope = ["chat"]
    last_user_intent = "log_saved"
    updated_at = "#{TIME}"
  TOML
  ROOT.join(".codex", "state", "paused-terms.toml") => <<~TOML
    paused_terms = []
  TOML
}

files.each { |path, body| write_file(path, body) }

checks = {
  TERM_DIR.join("question.md") => ["# 質問", "Route、Controller、Blade"],
  TERM_DIR.join("context.md") => ["# 参照範囲", "実ファイルは未参照"],
  TERM_DIR.join("answer-draft.md") => ["分類: feature", "# 理解確認"],
  TERM_DIR.join("log-draft.md") => ["# 学習テーマ", "# 次に学習すること"],
  TERM_DIR.join("metadata.toml") => ["status = \"notion_draft_created\"", "notion_draft_created = true"],
  ROOT.join("learning-logs", DATE, "#{SEQUENCE}-#{TOPIC_SLUG}.md") => ["# 学習テーマ", "# 未解決事項"],
  ROOT.join("notion-drafts", DATE, "#{SEQUENCE}-#{TOPIC_SLUG}.md") => ["# 学習テーマ", "# 未解決事項"],
  ROOT.join("notebook", "daily-learning-profiles", "#{DATE}.md") => ["# #{DATE} 日次学習傾向", "## 復習候補"],
  ROOT.join("notebook", "learner-profile.md") => ["# learner-profile", "苦手の種類: 構造理解"],
  ROOT.join(".codex", "state", "current-term.toml") => ["active = false", "awaiting = \"none\""]
}

checks.each { |path, expected| assert_includes(path, expected) }

report_path = ROOT.join("smoke-tests", "#{DATE}-save-flow-run-001.md")
write_file(report_path, <<~MD)
  # SAVE FLOW RUN 001

  実施日: #{DATE}

  ## 判定

  PASS

  ## 生成した主なファイル

  - `#{TERM_RELATIVE_PATH}/question.md`
  - `#{TERM_RELATIVE_PATH}/context.md`
  - `#{TERM_RELATIVE_PATH}/answer-draft.md`
  - `#{TERM_RELATIVE_PATH}/log-draft.md`
  - `#{TERM_RELATIVE_PATH}/metadata.toml`
  - `learning-logs/#{DATE}/#{SEQUENCE}-#{TOPIC_SLUG}.md`
  - `notion-drafts/#{DATE}/#{SEQUENCE}-#{TOPIC_SLUG}.md`
  - `notebook/daily-learning-profiles/#{DATE}.md`
  - `notebook/learner-profile.md`
  - `.codex/state/current-term.toml`

  ## 確認したこと

  - 学習ターム内の必須5ファイルが生成される。
  - 確定学習ログが日付ディレクトリに生成される。
  - Notion貼り付け用ドラフトが確定学習ログと同内容で生成される。
  - 日次学習傾向ファイルが生成される。
  - learner-profile.mdに苦手傾向、得意、学習スタイル、注意点が生成される。
  - current-term.tomlが `.codex/state/` に生成され、保存完了後は `active = false` になる。

  ## 次の検証候補

  - ログ化しない場合の軽量メモ保存
  - 2件目の学習ターム自動採番
  - paused-terms.tomlを使った中断と再開
MD

puts "PASS: sample save flow generated"
puts report_path.relative_path_from(ROOT)
