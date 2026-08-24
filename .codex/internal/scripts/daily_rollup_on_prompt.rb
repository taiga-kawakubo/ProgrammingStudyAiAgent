#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"

module ProgrammingAI
  class DailyRollupOnPrompt
    CLASSIFICATIONS = %w[feature unit assess error].freeze
    WEAKNESS_TYPES = %w[技術知識 構造理解 思考プロセス].freeze

    def initialize(root:, today:)
      @root = File.expand_path(root)
      @today = today
      @yesterday = today - 1
    end

    def run
      FileUtils.mkdir_p(daily_profile_dir)
      FileUtils.mkdir_p(briefing_dir)

      ensure_daily_profile
      return if File.exist?(briefing_path)

      write(briefing_path, build_mentor_briefing)
      puts "ProgrammingAI日次メモ: #{relative(briefing_path)} を作成しました。学習開始または最初の学習質問では、このファイルを読んでmentor出力を先に表示し、その後に質問へ回答してください。"
    rescue StandardError => error
      warn "ProgrammingAI daily rollup skipped: #{error.class}: #{error.message}"
      exit 0
    end

    private

    attr_reader :root, :today, :yesterday

    def ensure_daily_profile
      return false if File.exist?(daily_profile_path)
      return false unless File.exist?(learning_case_path)

      write(daily_profile_path, build_daily_profile)
      true
    end

    def build_daily_profile
      body = read(learning_case_path)
      stats = analyze_text(body)

      <<~MARKDOWN
        ## #{yesterday} 日次学習傾向

        生成元: [learning-cases/#{yesterday}.md](../../learning-cases/#{yesterday}.md)
        生成方法: UserPromptSubmit hook による日次処理

        ### この日の傾向

        #{classification_lines(stats)}

        ### 苦手種類候補の集計

        #{count_lines(stats[:weakness_counts], WEAKNESS_TYPES)}

        ### 観察パターン

        #{list_lines(stats[:observation_patterns])}

        ### 関連技術語

        #{list_lines(stats[:related_terms])}

        ### 繰り返し候補

        #{repeat_lines(stats[:observation_counts])}

        ### learner-profile / Memory 反映候補

        #{reflection_lines(stats)}
      MARKDOWN
    end

    def build_mentor_briefing
      recent_profiles = recent_daily_profiles
      recent_body = recent_profiles.map { |path| read(path) }.join("\n")
      stats = analyze_text(recent_body)
      source_lines = recent_profiles.map { |path| "- #{relative(path)}" }
      source_lines = ["- 前日のLearning Caseまたは日次学習傾向ファイルはまだありません。"] if source_lines.empty?

      <<~MARKDOWN
        # #{today} 学習前メモ

        生成方法: UserPromptSubmit hook による日次処理

        ## 生成元

        #{source_lines.join("\n")}

        ## 最近の学習傾向

        #{trend_lines(stats)}

        ## 復習

        Q. #{review_question(stats)}

        <details>
        <summary>A</summary>

        #{review_answer(stats)}

        </details>

        ## 最初に意識する確認ポイント

        #{focus_lines(stats)}

        ## learner-profile / Memory 反映候補

        #{reflection_lines(stats)}
      MARKDOWN
    end

    def analyze_text(text)
      classifications = extract_classifications(text)
      weakness_types = extract_values(text, "苦手種類候補")
      observation_patterns = extract_values(text, "観察パターン")
      related_terms = extract_values(text, "関連技術語").flat_map { |value| split_terms(value) }

      {
        classification_counts: count_values(classifications, CLASSIFICATIONS),
        weakness_counts: count_values(weakness_types, WEAKNESS_TYPES),
        observation_patterns: observation_patterns.uniq,
        observation_counts: tally_values(observation_patterns),
        related_terms: related_terms.uniq
      }
    end

    def extract_classifications(text)
      values = []
      lines = text.lines.map(&:strip)
      lines.each_with_index do |line, index|
        if line == "# 質問分類"
          value = next_body_line(lines, index)
          values << value if value
        elsif line.start_with?("分類:")
          values << line.sub("分類:", "").strip
        end
      end
      values.select { |value| CLASSIFICATIONS.include?(value) }
    end

    def extract_values(text, heading)
      values = []
      lines = text.lines.map(&:strip)
      lines.each_with_index do |line, index|
        if line == "# #{heading}" || line == "## #{heading}" || line == "### #{heading}"
          value = next_body_line(lines, index)
          values << normalize_list_value(value) if value
        elsif line.start_with?("#{heading}:")
          value = line.sub("#{heading}:", "").strip
          values << normalize_list_value(value) unless value.empty?
        end
      end
      values.reject(&:empty?)
    end

    def next_body_line(lines, index)
      lines[(index + 1)..]&.find { |candidate| body_line?(candidate) }
    end

    def body_line?(line)
      !line.empty? && !line.start_with?("#")
    end

    def normalize_list_value(value)
      value.to_s.sub(/\A[-*]\s*/, "").strip
    end

    def split_terms(value)
      value.split(/[、,]/).map(&:strip).reject(&:empty?)
    end

    def count_values(values, keys)
      counts = keys.to_h { |key| [key, 0] }
      values.each { |value| counts[value] += 1 if counts.key?(value) }
      counts
    end

    def tally_values(values)
      values.each_with_object(Hash.new(0)) { |value, counts| counts[value] += 1 }
    end

    def classification_lines(stats)
      count_lines(stats[:classification_counts], CLASSIFICATIONS)
    end

    def count_lines(counts, keys)
      keys.map { |key| "#{key}: #{counts.fetch(key, 0)}件" }.join("\n")
    end

    def list_lines(values)
      return "- まだ記録がありません。" if values.empty?

      values.map { |value| "- #{value}" }.join("\n")
    end

    def repeat_lines(counts)
      repeats = counts.select { |_key, count| count >= 2 }
      return "- まだ明確な繰り返し候補はありません。" if repeats.empty?

      repeats.map { |value, count| "- #{value}: #{count}回" }.join("\n")
    end

    def trend_lines(stats)
      observations = stats[:observation_patterns]
      terms = stats[:related_terms]
      lines = []
      lines << "直近の日次学習傾向から、質問分類と観察パターンを確認します。"
      lines << "観察パターン: #{observations.first(3).join(' / ')}" unless observations.empty?
      lines << "関連技術語: #{terms.first(5).join('、')}" unless terms.empty?
      lines.join("\n\n")
    end

    def review_question(stats)
      pattern = stats[:observation_patterns].first
      return "昨日または最近の学習で、最初にどこから確認するかを1つ思い出してください。" unless pattern

      "「#{pattern}」に近い場面では、最初に何を確認しますか。"
    end

    def review_answer(stats)
      pattern = stats[:observation_patterns].first
      return "質問の入口、対象ファイル、エラーや出力、次に渡る処理を順番に確認します。" unless pattern

      "まず入口と対象範囲を確認し、次に処理の流れ、最後に出力や保存先を確認します。今回の観察パターンは「#{pattern}」です。"
    end

    def focus_lines(stats)
      if stats[:observation_patterns].empty?
        "- 質問するときは、見てほしいファイルやエラー文などの参照範囲を先に指定する。"
      else
        "- 昨日または最近の観察パターンを1つ思い出してから、入口、処理、出力の順に確認する。"
      end
    end

    def reflection_lines(stats)
      repeats = stats[:observation_counts].select { |_key, count| count >= 2 }
      return "- 長期傾向へ反映する候補はまだありません。" if repeats.empty?

      repeats.map do |value, count|
        "- learner-profile / Memory反映候補: #{value} (#{count}回)。学習者の肯定または修正後に長期傾向へ反映する。"
      end.join("\n")
    end

    def recent_daily_profiles
      paths = Dir.glob(File.join(daily_profile_dir, "*.md")).sort
      paths.select do |path|
        date = Date.parse(File.basename(path, ".md"))
        date < today && date >= today - 7
      rescue ArgumentError
        false
      end
    end

    def daily_profile_dir
      File.join(root, "notebook", "daily-learning-profiles")
    end

    def briefing_dir
      File.join(root, "notebook", "mentor-briefings")
    end

    def learning_case_path
      File.join(root, "learning-cases", "#{yesterday}.md")
    end

    def daily_profile_path
      File.join(daily_profile_dir, "#{yesterday}.md")
    end

    def briefing_path
      File.join(briefing_dir, "#{today}.md")
    end

    def read(path)
      File.read(path)
    end

    def write(path, body)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
    end

    def relative(path)
      path.delete_prefix("#{root}/")
    end
  end
end

root = ENV.fetch("PROGRAMMING_AI_PROJECT_ROOT", File.expand_path("../../..", __dir__))
today = Date.parse(ENV.fetch("PROGRAMMING_AI_TODAY", Date.today.to_s))

ProgrammingAI::DailyRollupOnPrompt.new(root: root, today: today).run
