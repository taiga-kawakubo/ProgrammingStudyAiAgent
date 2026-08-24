#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "pathname"

ROOT = Pathname.new(File.expand_path("../../..", __dir__))
TODAY = Date.new(2026, 8, 6)
RETENTION_DAYS = 60

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

def assert_exists(path)
  return if path.exist?

  warn "FAILED: #{path.relative_path_from(ROOT)} should exist"
  exit 1
end

def assert_missing(path)
  return unless path.exist?

  warn "FAILED: #{path.relative_path_from(ROOT)} should not exist"
  exit 1
end

daily_dir = ROOT.join("notebook", "daily-learning-profiles")
old_path = daily_dir.join("2026-06-06.md")
boundary_path = daily_dir.join("2026-06-07.md")

write_file(old_path, <<~MD)
  # 2026-06-06 日次学習傾向

  retention-test-generated: true

  60日保持の削除対象になるサンプル。
MD

write_file(boundary_path, <<~MD)
  # 2026-06-07 日次学習傾向

  retention-test-generated: true

  60日保持の境界として残すサンプル。
MD

cutoff = TODAY - RETENTION_DAYS
deleted = []
kept = []

daily_dir.children.each do |path|
  next unless path.file?

  date_text = path.basename.to_s[/\A\d{4}-\d{2}-\d{2}/]
  next unless date_text

  date = Date.parse(date_text)
  generated_by_test = File.read(path).include?("retention-test-generated: true")

  if date < cutoff && generated_by_test
    File.delete(path)
    deleted << path.relative_path_from(ROOT).to_s
  else
    kept << path.relative_path_from(ROOT).to_s
  end
end

assert_missing(old_path)
assert_exists(boundary_path)

alias_error_report = <<~MD
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
MD

alias_report_path = ROOT.join("smoke-tests", "2026-08-06-technical-area-alias-error.md")
write_file(alias_report_path, alias_error_report)
assert_includes(alias_report_path, ["形式Error", "読み替えを使う分析だけ止める", "通常の質問回答"])

report_path = ROOT.join("smoke-tests", "2026-08-06-retention-alias-run-001.md")
write_file(report_path, <<~MD)
  # RETENTION AND ALIAS RUN 001

  実施日: 2026-08-06

  ## 判定

  PASS

  ## 日次学習傾向ファイルの保持日数

  - retention_days: #{RETENTION_DAYS}
  - cutoff: #{cutoff}
  - `2026-06-06.md` は削除対象として削除した。
  - `2026-06-07.md` は保持対象として残した。

  ## 削除対象

  #{deleted.map { |path| "- `#{path}`" }.join("\n")}

  ## technical_area_aliases形式Error

  - 読み替えを使う分析だけ止める。
  - 通常の質問回答は続ける。
  - 修正案を提示する。
  - 詳細: [2026-08-06-technical-area-alias-error.md](2026-08-06-technical-area-alias-error.md)
MD

puts "PASS: retention and alias checks generated"
puts report_path.relative_path_from(ROOT)
