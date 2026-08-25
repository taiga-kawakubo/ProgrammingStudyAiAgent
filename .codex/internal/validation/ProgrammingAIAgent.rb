#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

module ProgrammingAI
  VERSION = "2.4.0-config-classification-status-and-log-location-validation"
  PROJECT_ROOT = File.expand_path("../../..", __dir__)

  VALID_CLASSIFICATIONS = %w[feature unit assess error].freeze
  VALID_STATUSES = %w[in_progress completed].freeze

  # configのバリデーションの定義
  CONFIG_SCHEMA = {
    "mentor_start_advice_mode" => { type: :string, required: true, allowed: %w[manual daily_first_question] },
    "agent_trace_mode" => { type: :string, required: true, allowed: %w[hidden brief detailed] },
    "scope_listing_max_depth" => { type: :integer, required: true, min: 0, max: 5 }
  }.freeze

  # .codex/config.toml を読み取って、Rubyで扱いやすいHashに変換するための補助クラス
  class SimpleToml
    def self.parse(text)  #SimpleToml.parse(text) という形で呼べるメソッドを定義。self.parse と書くことでインスタンスを作らずに呼べます
      result = {}
      text.each_line do |raw|  #一行ずつ処理する
        line = raw.strip  #文字列の前後の空白や改行を取り除く
        next if line.empty? || line.start_with?("#") || line.start_with?("[[")  #読み飛ばす行の設定　空行, #から始まる行, [[...]] から始まる行

        key, value = line.split("=", 2).map(&:strip)  #split("=", 2) 1行を = で最大2つに分ける　map(&:strip)：前後の空白を消す
        next unless key && value  #key と value の両方が存在しない行はスキップ

        result[key] = parse_value(value)  #Hashに設定値を保存。parse_value()は文字列を値にするメソッド。
      end
      result  #作成したHashを返す
    end

    def self.parse_value(value)  #parse_value()メソッドの定義
      if value.start_with?('"') && value.end_with?('"')
        value[1..-2]
      elsif value.start_with?("[") && value.end_with?("]")
        inner = value[1..-2].strip
        return [] if inner.empty?

        split_array(inner).map { |item| parse_value(item.strip) }
      elsif value.match?(/\A-?\d+\z/)
        value.to_i
      elsif value == "true"
        true
      elsif value == "false"
        false
      else
        value
      end
    end

    def self.split_array(inner)  #配列の中身をカンマで分けるためのメソッド
      parts = []  #分割後の要素を入れる配列
      current = +""  #受け取った値を入れて、条件に一致したらpartsに保存し空にする
      in_string = false  #""の中にいるかどうかの確認。falseは外ということ
      inner.each_char do |char|  #innerを一文字ずつ見ていくということ。メソッドが使用された際の引数を見ていくということ。
        if char == '"'
          in_string = !in_string  #一つ目の"で内にいる状態となり、二つ目の"で外にいる状態となる。
          current << char  #<<は末尾に文字列を加える演算子。値を parts に追加
        elsif char == "," && !in_string
          parts << current
          current = +""
        else
          current << char
        end
      end
      parts << current unless current.empty?
      parts  #partsを返す。Rubyでは、メソッドの最後に書かれた値が返り値になる。
    end
  end

  # configと保存済み分類ラベルの検証クラス
  class ProjectValidator
    attr_reader :root, :errors, :warnings  #外側から使用できるものを指定

    def initialize(root)  #検証に必要な初期状態を作る
      @root = File.expand_path(root)  #プロジェクトルートの絶対パス
      @errors = []
      @warnings = []
    end

    def run  #検証処理の順番を指定
      check_config
      check_classification_labels
      check_learning_case_statuses
      check_learning_logs_index_dirs_absent
      result
    end

    def result  #最後に検証結果をまとめる
      {
        ok: errors.empty?,  #エラーが空かどうかを確認。なければtrue,あればfalse
        errors: errors,
        warnings: warnings
      }
    end

    private

    def path(relative_path)
      File.join(root, relative_path)  #プロジェクト内の README.md の絶対パスを作る。File.join は、パスを安全につなげるRubyのメソッド
    end

    def read(relative_path)
      File.read(path(relative_path))  #プロジェクト内のファイルを読み込む。
    end

    def exist?(relative_path)
      File.exist?(path(relative_path))  #プロジェクト内にそのファイルやディレクトリが存在するか確認。
    end

    def check_config  #configが存在するか確認し、中身を読み取り、必須キーが存在するか、値がルールにあっているか、未定義のキーが無いか確認
      unless exist?(".codex/config.toml")
        errors << "missing config file: .codex/config.toml"
        return
      end

      config = SimpleToml.parse(read(".codex/config.toml"))
      CONFIG_SCHEMA.each do |key, spec|
        if spec[:required] && !config.key?(key)
          errors << "missing config key: #{key}"
          next
        end
        next unless config.key?(key)

        validate_config_value(key, config[key], spec)
      end

      unknown = config.keys - CONFIG_SCHEMA.keys
      unknown.each { |key| warnings << "unknown config key: #{key}" }
    end

    def validate_config_value(key, value, spec)
      type_ok = case spec[:type]
                when :string then value.is_a?(String)
                when :integer then value.is_a?(Integer)
                when :array then value.is_a?(Array)
                when :string_array then value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
                when :integer_array then value.is_a?(Array) && value.all? { |item| item.is_a?(Integer) }
                else true
                end
      unless type_ok
        errors << "#{key}: invalid type"
        return
      end

      errors << "#{key}: value not allowed" if spec[:allowed] && !spec[:allowed].include?(value)
      if value.is_a?(Array) && spec[:allowed_items]
        invalid = value - spec[:allowed_items]
        errors << "#{key}: invalid items #{invalid.join(", ")}" unless invalid.empty?
      end
      errors << "#{key}: below min" if spec[:min] && value.is_a?(Integer) && value < spec[:min]
      errors << "#{key}: above max" if spec[:max] && value.is_a?(Integer) && value > spec[:max]
      if value.is_a?(Array) && spec[:min_item]
        errors << "#{key}: item below min" if value.any? { |item| item.is_a?(Integer) && item < spec[:min_item] }
      end
      if value.is_a?(Array) && spec[:max_item]
        errors << "#{key}: item above max" if value.any? { |item| item.is_a?(Integer) && item > spec[:max_item] }
      end
    end

    # 質問の分類ラベルが正しいか確認する処理
    def check_classification_labels
      classification_entries.each do |source, value|
        next if VALID_CLASSIFICATIONS.include?(value)

        errors << "#{source}: invalid classification #{value.inspect}"
      end
    end

    def check_learning_case_statuses
      status_entries.each do |source, value|
        next if VALID_STATUSES.include?(value)

        errors << "#{source}: invalid status #{value.inspect}"
      end
    end

    def check_learning_logs_index_dirs_absent
      %w[learning-logs/inbox learning-logs/outbox].each do |relative_path|
        errors << "#{relative_path} is not allowed" if exist?(relative_path)
      end
    end

    def classification_entries
      files = Dir.glob(File.join(root, "{learning-cases,learning-logs,.codex/agents/mentor}", "**", "*.md"), File::FNM_EXTGLOB)
      files.flat_map do |file|
        source = file.delete_prefix("#{root}/")
        extract_classifications(File.read(file)).map { |value| [source, value] }
      end
    end

    def extract_classifications(text)
      values = []
      lines = text.lines.map(&:strip)
      lines.each_with_index do |line, index|
        if line == "# 質問分類"
          value = lines[(index + 1)..]&.find { |candidate| !candidate.empty? && !candidate.start_with?("#") }
          values << value if value
        elsif line.start_with?("分類:")
          values << line.sub("分類:", "").strip
        end
      end
      values
    end

    def status_entries
      files = Dir.glob(File.join(root, "{learning-cases,learning-logs}", "**", "*.md"), File::FNM_EXTGLOB)
      files.flat_map do |file|
        source = file.delete_prefix("#{root}/")
        extract_statuses(File.read(file)).map { |value| [source, value] }
      end
    end

    def extract_statuses(text)
      text.lines.each_with_object([]) do |line, values|
        match = line.strip.match(/\Astatus:\s*(\S+)/)
        values << match[1] if match
      end
    end
  end

  class CLI
    def self.run(argv)
      command = argv.shift || "test"
      case command
      when "test", "validate"
        validator = ProjectValidator.new(PROJECT_ROOT)
        result = validator.run
        if result[:ok]
          puts "PASS: ProgrammingAI config, classification, status, and log location validation"
          puts JSON.pretty_generate(result) unless result[:warnings].empty?
        else
          warn JSON.pretty_generate(result)
          exit 1
        end
      when "help"
        puts "Usage: ruby .codex/internal/validation/ProgrammingAIAgent.rb [test|validate|help]"
      else
        warn "Unknown command: #{command}"
        exit 1
      end
    end
  end
end

ProgrammingAI::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
