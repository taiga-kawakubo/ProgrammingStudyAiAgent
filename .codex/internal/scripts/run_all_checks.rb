#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "pathname"

ROOT = Pathname.new(File.expand_path("../../..", __dir__))
DATE = "2026-08-06"

checks = [
  ".codex/internal/scripts/run_sample_save_flow.rb",
  ".codex/internal/scripts/run_additional_flow_checks.rb",
  ".codex/internal/scripts/run_resume_flow_check.rb",
  ".codex/internal/scripts/run_retention_and_alias_checks.rb"
]

results = []

checks.each do |script|
  stdout, stderr, status = Open3.capture3("ruby", script, chdir: ROOT.to_s)
  results << {
    script: script,
    success: status.success?,
    stdout: stdout,
    stderr: stderr
  }

  next if status.success?

  warn "FAILED: #{script}"
  warn stderr
  warn stdout
  exit 1
end

report_path = ROOT.join("smoke-tests", "#{DATE}-all-checks-run-001.md")
report = <<~MD
  # ALL CHECKS RUN 001

  実施日: #{DATE}

  ## 判定

  PASS

  ## 実行順序

MD

results.each_with_index do |result, index|
  report += <<~MD
    #{index + 1}. `#{result[:script]}`
       - result: PASS
       - output: #{result[:stdout].lines.first&.strip}

  MD
end

report += <<~MD
  ## 確認範囲

  - サンプル保存フロー
  - ログ化しない場合の軽量メモ
  - 2件目の自動採番
  - paused状態の作成
  - paused状態からの再開
  - 日次学習傾向ファイルの保持日数
  - technical_area_aliasesの形式Error

  ## 次の検証候補

  - 設定ファイルの欠損キー修復案
  - scope-readerの秘密情報停止
  - 実際の質問入力から保存までの対話型リハーサル
MD

File.write(report_path, report)

puts "PASS: all checks generated"
puts report_path.relative_path_from(ROOT)
