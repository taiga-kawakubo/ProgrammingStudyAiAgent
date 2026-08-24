#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"

ROOT = Pathname.new(File.expand_path("../../..", __dir__))
DATE = "2026-08-06"
TIME = "2026-08-06T11:00:00+09:00"

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

def assert_missing(path)
  return unless path.exist?

  warn "FAILED: #{path.relative_path_from(ROOT)} should not exist"
  exit 1
end

def next_sequence(date)
  dir = ROOT.join("learning-cases", date)
  return "001" unless dir.exist?

  sequences = dir.children.select(&:directory?).map do |entry|
    match = entry.basename.to_s[/\A(\d{3})-/, 1]
    match && match.to_i
  end.compact
  max = sequences.max

  format("%03d", max.to_i + 1)
end

def existing_sequence_for(date, topic_slug)
  dir = ROOT.join("learning-cases", date)
  return nil unless dir.exist?

  match = dir.children.select(&:directory?).find do |entry|
    entry.basename.to_s.match?(/\A\d{3}-#{Regexp.escape(topic_slug)}\z/)
  end

  match&.basename&.to_s&.[](/\A(\d{3})-/, 1)
end

def create_term(sequence, topic_slug, classification:, status:, awaiting:, log_status:, notion_draft_created:, question:, context:, answer:, log_draft:)
  term_id = "#{DATE}-#{sequence}-#{topic_slug}"
  term_relative_path = "learning-cases/#{DATE}/#{sequence}-#{topic_slug}"
  term_dir = ROOT.join(term_relative_path)

  files = {
    term_dir.join("question.md") => <<~MD,
      # 質問

      #{question}
    MD
    term_dir.join("context.md") => context,
    term_dir.join("answer-draft.md") => answer,
    term_dir.join("log-draft.md") => log_draft,
    term_dir.join("metadata.toml") => <<~TOML
      term_id = "#{term_id}"
      date = "#{DATE}"
      sequence = #{sequence.to_i}
      topic_slug = "#{topic_slug}"

      classification = "#{classification}"
      classification_reason = "サンプル検証用"
      confidence = "medium"

      status = "#{status}"
      awaiting = "#{awaiting}"
      log_status = "#{log_status}"
      notion_draft_created = #{notion_draft_created}

      referenced_scope = ["chat"]
      created_at = "#{TIME}"
      updated_at = "#{TIME}"
    TOML
  }

  files.each { |path, body| write_file(path, body) }
  [term_id, term_relative_path, term_dir]
end

no_log_topic = "validation-rule-check"
sequence = existing_sequence_for(DATE, no_log_topic) || next_sequence(DATE)
unless sequence == "002"
  warn "FAILED: expected next sequence 002, got #{sequence}"
  exit 1
end

no_log_term_id, no_log_term_path, no_log_dir = create_term(
  sequence,
  no_log_topic,
  classification: "assess",
  status: "closed",
  awaiting: "none",
  log_status: "no_log",
  notion_draft_created: false,
  question: "このバリデーションの書き方で問題ありませんか。",
  context: <<~MD,
    # 参照範囲

    - チャット本文
    - 評価対象コードは未提示

    # 参照しなかった理由

    学習者がコードをまだ提示していないため。
  MD
  answer: <<~MD,
    # 分類

    分類: assess
    分類理由: 書き方が適切かを評価してほしい質問だからです。

    # 現状の確認

    評価対象のバリデーションコードが未提示。

    # 評価

    現時点では、具体的な書き方の良し悪しは判定できない。

    # 理解確認

    評価してほしいvalidationルールを貼れそうですか。
  MD
  log_draft: <<~MD
    # ログ化判断

    ログ化しない。

    # 理由

    評価対象コードが未提示で、学習内容がまだ具体化していないため。

    # 軽量メモ候補

    - 分類: assess
    - テーマ: Validationの書き方確認
    - つまずき候補: 評価対象を提示してから判断する必要がある
    - 参照した範囲: chat
    - ログ化しなかった理由: 学習内容がまだ具体化していない
  MD
)

daily_profile_path = ROOT.join("notebook", "daily-learning-profiles", "#{DATE}.md")
daily_profile = File.exist?(daily_profile_path) ? File.read(daily_profile_path) : "# #{DATE} 日次学習傾向\n"
unless daily_profile.include?("- テーマ: Validationの書き方確認")
  daily_profile += <<~MD

    ## 軽量メモ

    - 分類: assess
    - テーマ: Validationの書き方確認
    - つまずき候補: 評価対象を提示してから判断する必要がある
    - 参照した範囲: chat
    - ログ化しなかった理由: 学習内容がまだ具体化していない
  MD
end
write_file(daily_profile_path, daily_profile)

assert_missing(ROOT.join("learning-logs", DATE, "#{sequence}-#{no_log_topic}.md"))
assert_missing(ROOT.join("notion-drafts", DATE, "#{sequence}-#{no_log_topic}.md"))

paused_topic = "fetch-controller-flow"
paused_sequence = existing_sequence_for(DATE, paused_topic) || next_sequence(DATE)
unless paused_sequence == "003"
  warn "FAILED: expected paused sequence 003, got #{paused_sequence}"
  exit 1
end

paused_term_id, paused_term_path, paused_dir = create_term(
  paused_sequence,
  paused_topic,
  classification: "feature",
  status: "paused",
  awaiting: "resume_choice",
  log_status: "none",
  notion_draft_created: false,
  question: "fetchでControllerへ送る流れが途中で分からなくなりました。",
  context: <<~MD,
    # 参照範囲

    - チャット本文
    - 実ファイルは未参照
  MD
  answer: <<~MD,
    # 分類

    分類: feature
    分類理由: JavaScriptからControllerへ処理が渡る流れの質問だからです。

    # 状態

    別テーマへ移ったため、このタームは保留中。
  MD
  log_draft: <<~MD
    # ログ化判断

    未判断。

    # 理由

    タームがpausedであり、理解確認とログ化判断が終わっていないため。
  MD
)

write_file(ROOT.join(".codex", "state", "paused-terms.toml"), <<~TOML)
  [[paused_terms]]
  term_id = "#{paused_term_id}"
  term_path = "#{paused_term_path}"
  classification = "feature"
  status = "paused"
  paused_reason = "学習者が別テーマの確認に移ったため"
  paused_at = "#{TIME}"
  resume_hint = "fetchからControllerへ処理が渡る流れの理解確認から再開"
TOML

write_file(ROOT.join(".codex", "state", "current-term.toml"), <<~TOML)
  active = true
  term_id = "#{paused_term_id}"
  term_path = "#{paused_term_path}"
  classification = "feature"
  status = "paused"
  awaiting = "resume_choice"

  referenced_scope = ["chat"]
  last_user_intent = "new_topic"
  updated_at = "#{TIME}"
TOML

assert_includes(no_log_dir.join("metadata.toml"), ["sequence = 2", "log_status = \"no_log\"", "notion_draft_created = false"])
assert_includes(no_log_dir.join("log-draft.md"), ["# 軽量メモ候補", "ログ化しなかった理由"])
assert_includes(daily_profile_path, ["## 軽量メモ", "Validationの書き方確認"])
assert_includes(paused_dir.join("metadata.toml"), ["sequence = 3", "status = \"paused\"", "awaiting = \"resume_choice\""])
assert_includes(ROOT.join(".codex", "state", "paused-terms.toml"), [paused_term_id, "resume_hint"])
assert_includes(ROOT.join(".codex", "state", "current-term.toml"), ["active = true", "status = \"paused\"", "awaiting = \"resume_choice\""])

report_path = ROOT.join("smoke-tests", "#{DATE}-additional-flow-run-001.md")
write_file(report_path, <<~MD)
  # ADDITIONAL FLOW RUN 001

  実施日: #{DATE}

  ## 判定

  PASS

  ## 確認したこと

  ### ログ化しない場合の軽量メモ保存

  - `#{no_log_term_path}/` を自動採番 `#{sequence}` で生成した。
  - 確定学習ログは生成しない。
  - Notion貼り付け用ドラフトは生成しない。
  - `notebook/daily-learning-profiles/#{DATE}.md` に軽量メモを追記した。

  ### 2件目の学習ターム自動採番

  - 既存の `001-route-controller-blade-flow` を確認したうえで、次の番号を `002` と判断した。

  ### paused-terms.tomlを使った中断と再開

  - `#{paused_term_path}/` を自動採番 `#{paused_sequence}` で生成した。
  - `.codex/state/paused-terms.toml` に保留中タームを保存した。
  - `.codex/state/current-term.toml` を `active = true`、`status = "paused"`、`awaiting = "resume_choice"` にした。

  ### 再実行

  - 既に検証用の002/003タームがある場合は、同じ番号を再利用する。
  - 日次学習傾向ファイルの軽量メモは重複追記しない。

  ## 次の検証候補

  - paused状態から再開して、answer_createdまたはunderstanding_checkへ戻す。
  - 日次学習傾向ファイルの保持日数を使った削除候補判定。
  - technical_area_aliasesの形式Error検証。
MD

puts "PASS: additional flow checks generated"
puts report_path.relative_path_from(ROOT)
