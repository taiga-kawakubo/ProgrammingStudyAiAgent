#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"

module ProgrammingAI
  class InboxStatusOnPrompt
    VALID_STATUSES = %w[in_progress completed].freeze
    DEFAULT_TOPIC = "Uncategorized"

    Record = Struct.new(
      :case_id,
      :status,
      :main_topic,
      :related_terms,
      :title,
      :source_path,
      :next_action,
      keyword_init: true
    )

    def initialize(root:)
      @root = File.expand_path(root)
    end

    def run
      cases = collect_learning_cases

      rebuild_case_indexes(cases)
      print_in_progress_notice(cases)
    rescue StandardError => error
      warn "ProgrammingAI inbox status skipped: #{error.class}: #{error.message}"
      exit 0
    end

    private

    attr_reader :root

    def collect_learning_cases
      Dir.glob(File.join(root, "learning-cases", "*.md")).sort.flat_map do |path|
        parse_learning_case_file(path)
      end
    end

    def parse_learning_case_file(path)
      split_case_sections(read(path)).each_with_index.map do |section, index|
        build_learning_case_record(path, section, index)
      end.compact
    end

    def split_case_sections(text)
      sections = []
      current = { heading: nil, body: +"" }

      text.each_line do |line|
        heading_match = line.match(/\A##\s+(\d{4}-\d{2}-\d{2}-\d{3}\b.*)\s*\z/)
        case_id_match = line.match(/\Acase_id:\s*(\d{4}-\d{2}-\d{2}-\d{3})\b/)

        if heading_match
          sections << current if current[:body].strip.include?("case_id:")
          current = { heading: heading_match[1].strip, body: +"" }
        elsif case_id_match && current[:body].strip.include?("case_id:")
          sections << current
          current = { heading: case_id_match[1], body: +line }
        else
          current[:body] << line
        end
      end

      sections << current if current[:body].strip.include?("case_id:")
      sections.empty? ? [{ heading: nil, body: text }] : sections
    end

    def build_learning_case_record(path, section, index)
      metadata = metadata_lines(section[:body])
      status = metadata["status"]
      return nil unless VALID_STATUSES.include?(status)

      heading_id = section[:heading]&.match(/\A(\d{4}-\d{2}-\d{2}-\d{3})\b/)&.[](1)
      case_id = metadata["case_id"] || heading_id || fallback_case_id(path, index)
      related_terms = split_terms(metadata["related_terms"] || metadata["関連技術語"])
      topic = normalize_topic(metadata["main_topic"] || related_terms.first || DEFAULT_TOPIC)

      Record.new(
        case_id: case_id,
        status: status,
        main_topic: topic,
        related_terms: related_terms,
        title: title_from(section[:heading], section[:body], case_id),
        source_path: relative(path),
        next_action: next_action_from(section[:body], metadata)
      )
    end

    def metadata_lines(text)
      text.lines.each_with_object({}) do |line, metadata|
        match = line.strip.match(/\A([A-Za-z_]+|関連技術語)\s*:\s*(.+)\z/)
        next unless match

        metadata[match[1]] = match[2].strip
      end
    end

    def title_from(heading, body, case_id)
      title = heading&.sub(/\A#{Regexp.escape(case_id)}\s*/, "")&.strip
      title = nil if title == "学習テーマ"
      title = case_id if title.nil? || title.empty?
      title
    end

    def next_action_from(body, metadata)
      metadata["next_action"] ||
        value_after_heading(body, "次に学習すること") ||
        value_after_heading(body, "未解決事項")
    end

    def value_after_heading(text, heading)
      lines = text.lines.map(&:strip)
      lines.each_with_index do |line, index|
        next unless line == "# #{heading}" || line == "## #{heading}" || line == "### #{heading}"

        value = lines[(index + 1)..]&.find { |candidate| body_line?(candidate) }
        return normalize_list_value(value) if value
      end
      nil
    end

    def body_line?(line)
      !line.empty? && !line.start_with?("#")
    end

    def normalize_list_value(value)
      value.to_s.sub(/\A[-*]\s*/, "").strip
    end

    def split_terms(value)
      value.to_s.split(/[、,]/).map(&:strip).reject(&:empty?)
    end

    def normalize_topic(value)
      topic = value.to_s.strip
      topic.empty? ? DEFAULT_TOPIC : topic
    end

    def fallback_case_id(path, index)
      "#{File.basename(path, ".md")}-#{format("%03d", index + 1)}"
    end

    def rebuild_case_indexes(cases)
      rebuild_index(
        "learning-cases/inbox",
        "inbox",
        cases.select { |record| record.status == "in_progress" }
      )
      rebuild_index(
        "learning-cases/outbox",
        "outbox",
        cases.select { |record| record.status == "completed" }
      )
    end

    def rebuild_index(relative_dir, label, records)
      dir = File.join(root, relative_dir)
      FileUtils.mkdir_p(dir)
      Dir.glob(File.join(dir, "*.md")).each { |path| File.delete(path) }

      grouped_records(records).each do |topic, topic_records|
        path = File.join(dir, "#{safe_filename(topic)}.md")
        File.write(path, index_body(relative_dir, label, topic, topic_records))
      end
    end

    def grouped_records(records)
      records.group_by(&:main_topic).sort.to_h.transform_values do |topic_records|
        topic_records.sort_by { |record| [record.source_path, record.case_id] }
      end
    end

    def index_body(relative_dir, label, topic, records)
      lines = [
        "# #{topic} #{label}",
        "",
        "生成方法: UserPromptSubmit hook による自動更新",
        "正本を移動せず、参照用リンクだけを並べます。",
        ""
      ]

      records.each do |record|
        lines << "- [#{record.case_id} #{record.title}](#{relative_link(relative_dir, record.source_path)})"
        lines << "  - status: #{record.status}"
        lines << "  - next: #{record.next_action}" if record.next_action && !record.next_action.empty?
        lines << "  - related_terms: #{record.related_terms.join(', ')}" unless record.related_terms.empty?
      end

      "#{lines.join("\n")}\n"
    end

    def print_in_progress_notice(cases)
      in_progress = cases.select { |record| record.status == "in_progress" }
      return if in_progress.empty?

      topic_counts = in_progress.each_with_object(Hash.new(0)) do |record, counts|
        counts[record.main_topic] += 1
      end.sort_by { |topic, _count| topic }

      visible = topic_counts.first(3).map { |topic, count| "#{topic} #{count}件" }
      remaining = topic_counts.length - visible.length
      visible << "ほか#{remaining}分野" if remaining.positive?

      puts "ProgrammingAI未完了メモ: 未完了の学習テーマが#{in_progress.length}件あります。#{visible.join('、')}。必要なら「前の続き」と聞いてください。"
    end

    def safe_filename(value)
      name = value.to_s.strip.gsub(/[\/\\:*?"<>|]/, "-").gsub(/\s+/, "-")
      name.empty? ? DEFAULT_TOPIC : name
    end

    def relative_link(from_relative_dir, target_relative_path)
      from = Pathname.new(File.join(root, from_relative_dir))
      target = Pathname.new(File.join(root, target_relative_path))
      target.relative_path_from(from).to_s
    end

    def read(path)
      File.read(path)
    end

    def relative(path)
      path.delete_prefix("#{root}/")
    end
  end
end

root = ENV.fetch("PROGRAMMING_AI_PROJECT_ROOT", File.expand_path("../../..", __dir__))
ProgrammingAI::InboxStatusOnPrompt.new(root: root).run
