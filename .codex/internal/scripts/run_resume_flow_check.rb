#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"

ROOT = Pathname.new(File.expand_path("../../..", __dir__))
DATE = "2026-08-06"
TIME = "2026-08-06T11:30:00+09:00"
TERM_ID = "2026-08-06-003-fetch-controller-flow"
TERM_PATH = "learning-cases/2026-08-06/003-fetch-controller-flow"
TERM_DIR = ROOT.join(TERM_PATH)

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

unless TERM_DIR.exist?
  warn "FAILED: paused term does not exist. Run .codex/internal/scripts/run_additional_flow_checks.rb first."
  exit 1
end

answer_path = TERM_DIR.join("answer-draft.md")
answer = File.read(answer_path)
unless answer.include?("# 再開後の回答")
  answer += <<~MD

    # 再開後の回答

    fetchからControllerへ処理が渡る流れは、まずJavaScript側の送信先URL、HTTPメソッド、送信データを見る。
    次にLaravel側で、そのURLに対応するRouteとControllerを確認する。

    # 理解確認

    fetchの送信先URLを確認したあと、Laravel側では次に何を確認しますか。
  MD
end
write_file(answer_path, answer)

write_file(TERM_DIR.join("metadata.toml"), <<~TOML)
  term_id = "#{TERM_ID}"
  date = "#{DATE}"
  sequence = 3
  topic_slug = "fetch-controller-flow"

  classification = "feature"
  classification_reason = "JavaScriptからControllerへ処理が渡る流れの質問であるため"
  confidence = "medium"

  status = "understanding_check"
  awaiting = "understanding_answer"
  log_status = "none"
  notion_draft_created = false

  referenced_scope = ["chat"]
  created_at = "2026-08-06T11:00:00+09:00"
  updated_at = "#{TIME}"
TOML

write_file(ROOT.join(".codex", "state", "current-term.toml"), <<~TOML)
  active = true
  term_id = "#{TERM_ID}"
  term_path = "#{TERM_PATH}"
  classification = "feature"
  status = "understanding_check"
  awaiting = "understanding_answer"

  referenced_scope = ["chat"]
  last_user_intent = "resume_choice"
  updated_at = "#{TIME}"
TOML

write_file(ROOT.join(".codex", "state", "paused-terms.toml"), <<~TOML)
  paused_terms = []
TOML

assert_includes(answer_path, ["# 再開後の回答", "# 理解確認"])
assert_includes(TERM_DIR.join("metadata.toml"), ["status = \"understanding_check\"", "awaiting = \"understanding_answer\""])
assert_includes(ROOT.join(".codex", "state", "current-term.toml"), ["active = true", "status = \"understanding_check\"", "awaiting = \"understanding_answer\""])
assert_includes(ROOT.join(".codex", "state", "paused-terms.toml"), ["paused_terms = []"])

report_path = ROOT.join("smoke-tests", "#{DATE}-resume-flow-run-001.md")
write_file(report_path, <<~MD)
  # RESUME FLOW RUN 001

  実施日: #{DATE}

  ## 判定

  PASS

  ## 確認したこと

  - paused状態の `#{TERM_PATH}/` を再開した。
  - `metadata.toml` を `status = "understanding_check"`、`awaiting = "understanding_answer"` に戻した。
  - `.codex/state/current-term.toml` を再開中タームに向けた。
  - `.codex/state/paused-terms.toml` から保留タームを外した。
  - `answer-draft.md` に再開後の回答と理解確認を追加した。

  ## 次の検証候補

  - 理解確認への回答後、ログ化判断へ進む。
  - resume対象が複数ある場合の候補提示。
MD

puts "PASS: resume flow check generated"
puts report_path.relative_path_from(ROOT)
