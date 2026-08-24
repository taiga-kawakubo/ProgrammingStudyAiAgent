#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require "time"

PROJECT_ROOT = Pathname.new(File.expand_path("../../..", __dir__))
WORKSPACE_ROOT = PROJECT_ROOT.parent.parent
DEFAULT_OUTPUT = WORKSPACE_ROOT.join("outputs", "ProgrammingAI_project_single_file_2026-08-06.md")
OUTPUT = Pathname.new(ARGV[0] || DEFAULT_OUTPUT.to_s)
REQUIREMENTS = WORKSPACE_ROOT.join("outputs", "ProgrammingAI_requirements_development-ready_2026-08-06.md")

def language_for(path)
  case path.extname
  when ".md"
    "md"
  when ".toml"
    "toml"
  when ".rb"
    "ruby"
  else
    "text"
  end
end

def append_file(buffer, path, label)
  relative = path.relative_path_from(PROJECT_ROOT)
  buffer << "\n## #{label}: `#{relative}`\n\n"
  buffer << "````#{language_for(path)}\n"
  buffer << path.read
  buffer << "\n````\n"
end

unless REQUIREMENTS.exist?
  warn "Missing requirements file: #{REQUIREMENTS}"
  exit 1
end

project_files = PROJECT_ROOT.find.select(&:file?).reject do |path|
  path.basename.to_s == ".DS_Store"
end.sort_by { |path| path.relative_path_from(PROJECT_ROOT).to_s }

generated_at = Time.new(2026, 8, 6, 9, 30, 0, "+09:00").iso8601
buffer = +"# ProgrammingAI Project Single File Package\n\n"
buffer << "書き出し日時: #{generated_at}\n"
buffer << "保存形式: Markdown単一ファイル\n"
buffer << "状態: 開発着手可\n\n"
buffer << "このファイルは、ProgrammingAIの要件定義書、Project足場、Skill、検証ハーネス、検証ログを1つにまとめた開発用パッケージである。\n\n"
buffer << "## 使い方\n\n"
buffer << "1. まず `ProgrammingAI 要件定義書 開発着手版` を読む。\n"
buffer << "2. 次に `README.md`、`HARNESS_MAP.md`、`AGENTS.md`、`PROJECT_STRUCTURE.md`、`SMOKE_TEST.md` を読む。\n"
buffer << "3. 保守時は `.codex/internal/scripts/run_all_checks.rb` と各 `smoke-tests/` を回帰確認の基準にする。\n"
buffer << "4. この単一ファイルは配布・確認用であり、実装時は各ファイルへ展開して使用する。\n\n"
buffer << "## 含まれる内容\n\n"
buffer << "- 開発着手版の要件定義書\n"
buffer << "- ProgrammingAI Project足場\n"
buffer << "- `.codex/skills` のSkill定義\n"
buffer << "- `.codex/config.toml` と `.codex/config.defaults.toml`\n"
buffer << "- 学習ケース、学習ログ、Notionドラフト、notebookのサンプル\n"
buffer << "- 検証ハーネスと検証ログ\n\n"

buffer << "# ProgrammingAI 要件定義書 開発着手版\n\n"
buffer << REQUIREMENTS.read.sub(/\A# ProgrammingAI 要件定義書 開発着手版\n+/, "")
buffer << "\n\n# Project Files\n\n"

project_files.each_with_index do |path, index|
  append_file(buffer, path, format("%03d", index + 1))
end

OUTPUT.dirname.mkpath
OUTPUT.write(buffer)

puts "PASS: exported single file package"
puts OUTPUT
