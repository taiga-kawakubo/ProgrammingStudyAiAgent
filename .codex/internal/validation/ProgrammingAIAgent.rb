#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "stringio"
require "time"
require "tmpdir"

module ProgrammingAI
  VERSION = "1.0.0"
  PROJECT_ROOT = File.expand_path("../../..", __dir__)
  VALID_CLASSIFICATIONS = %w[feature unit assess error].freeze
  PROJECT_DATA_PREFIXES = ["learning-cases/", "learning-logs/", "notebook/", ".codex/agents/mentor/MEMORY.md"].freeze
  FORBIDDEN_WRITE_MARKERS = [
    "/.codex/memories/",
    "/extensions/ad_hoc/notes/",
    "/Users/taiga/.codex/memories/"
  ].freeze

  CONFIG_DEFAULTS = {
    "confirmation_mode" => "strict_stop",
    "mentor_start_advice_mode" => "daily_first_question",
    "agent_trace_mode" => "brief",
    "scope_access_mode" => "explicit_only",
    "scope_listing_max_depth" => 2,
    "daily_profile_retention_days" => 60,
    "weakness_review_interval_days" => 4,
    "profile_pending_review_interval_days" => 4,
    "review_offsets_days" => [1, 3, 7, 10],
    "review_question_count" => 1,
    "weakness_types" => %w[technical_knowledge structure_understanding thinking_process],
    "weakness_priority_order" => %w[technical_knowledge structure_understanding thinking_process],
    "review_eligible_confidence_levels" => %w[high medium],
    "weakness_confidence_visibility" => "hidden_by_default",
    "evidence_log_link_limit" => 3,
    "technical_area_candidates" => %w[Laravel Route Controller Blade JavaScript Fetch Validation Database Test],
    "technical_area_custom_candidates" => [],
    "technical_area_aliases" => [],
    "config_validation" => "enabled",
    "technical_area_alias_validation" => "enabled",
    "technical_area_alias_validation_error_mode" => "skip_alias_analysis_and_suggest_fix"
  }.freeze

  CONFIG_SCHEMA = {
    "confirmation_mode" => { type: :string, required: true, allowed: %w[strict_stop agent_decides] },
    "mentor_start_advice_mode" => { type: :string, required: true, allowed: %w[manual daily_first_question auto_on_start] },
    "agent_trace_mode" => { type: :string, required: true, allowed: %w[hidden brief detailed] },
    "scope_access_mode" => { type: :string, required: true, allowed: %w[explicit_only user_defined_depth broad_allowed] },
    "scope_listing_max_depth" => { type: :integer, required: true, min: 0, max: 5 },
    "daily_profile_retention_days" => { type: :integer, required: true, min: 1, max: 365 },
    "weakness_review_interval_days" => { type: :integer, required: true, min: 1, max: 30 },
    "profile_pending_review_interval_days" => { type: :integer, required: true, min: 1, max: 30 },
    "review_offsets_days" => { type: :integer_array, required: true, min_item: 1, max_item: 365 },
    "review_question_count" => { type: :integer, required: true, min: 1, max: 3 },
    "weakness_types" => { type: :string_array, required: true, allowed_items: %w[technical_knowledge structure_understanding thinking_process] },
    "weakness_priority_order" => { type: :string_array, required: true, allowed_items: %w[technical_knowledge structure_understanding thinking_process] },
    "review_eligible_confidence_levels" => { type: :string_array, required: true, allowed_items: %w[high medium low] },
    "weakness_confidence_visibility" => { type: :string, required: true, allowed: %w[hidden_by_default show_on_request] },
    "evidence_log_link_limit" => { type: :integer, required: true, min: 1, max: 3 },
    "technical_area_candidates" => { type: :string_array, required: true },
    "technical_area_custom_candidates" => { type: :string_array, required: true },
    "technical_area_aliases" => { type: :alias_array, required: true },
    "config_validation" => { type: :string, required: true, allowed: %w[enabled] },
    "technical_area_alias_validation" => { type: :string, required: true, allowed: %w[enabled disabled] },
    "technical_area_alias_validation_error_mode" => { type: :string, required: true, allowed: %w[skip_alias_analysis_and_suggest_fix] }
  }.freeze

  class FileStore
    attr_reader :root

    def initialize(root)
      @root = File.expand_path(root)
    end

    def path(*parts)
      File.join(root, *parts)
    end

    def write(relative_path, content)
      full_path = path(relative_path)
      validate_write_path!(relative_path, full_path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      full_path
    end

    def read(relative_path)
      File.read(path(relative_path))
    end

    def exist?(relative_path)
      File.exist?(path(relative_path))
    end

    def mkdir(relative_path)
      FileUtils.mkdir_p(path(relative_path))
    end

    def list(relative_path)
      dir = path(relative_path)
      return [] unless Dir.exist?(dir)

      Dir.children(dir).sort
    end

    def validate_write_path!(relative_path, full_path)
      expanded = File.expand_path(full_path)
      root_prefix = "#{root}/"
      unless expanded == root || expanded.start_with?(root_prefix)
        raise "write outside project root is not allowed: #{relative_path}"
      end
      if FORBIDDEN_WRITE_MARKERS.any? { |marker| expanded.include?(marker) }
        raise "ProgrammingAI learning data must not be saved to Codex global memory: #{relative_path}"
      end
      return unless PROJECT_DATA_PREFIXES.any? { |prefix| relative_path.start_with?(prefix) }
      return if ENV["PROGRAMMING_AI_ALLOW_TEST_ROOT"] == "1"
      return if root == PROJECT_ROOT

      raise "ProgrammingAI learning data must be saved under this Project folder: #{relative_path}"
    end
  end

  class SimpleToml
    def self.dump(hash)
      hash.map do |key, value|
        "#{key} = #{format_value(value)}"
      end.join("\n") + "\n"
    end

    def self.parse(text)
      result = {}
      current_array_key = nil
      text.each_line do |raw|
        line = raw.strip
        next if line.empty? || line.start_with?("#")

        if line.start_with?("[[") && line.end_with?("]]")
          current_array_key = line[2..-3]
          result[current_array_key] ||= []
          result[current_array_key] << {}
          next
        end

        key, value = line.split("=", 2).map(&:strip)
        next unless key && value

        parsed = parse_value(value)
        if current_array_key
          result[current_array_key].last[key] = parsed
        else
          result[key] = parsed
        end
      end
      result
    end

    def self.format_value(value)
      case value
      when String
        value.inspect
      when Integer
        value.to_s
      when TrueClass, FalseClass
        value.to_s
      when Array
        "[" + value.map { |item| format_value(item) }.join(", ") + "]"
      else
        value.inspect
      end
    end

    def self.parse_value(value)
      if value.start_with?('"') && value.end_with?('"')
        value[1..-2]
      elsif value == "true"
        true
      elsif value == "false"
        false
      elsif value.start_with?("[") && value.end_with?("]")
        inner = value[1..-2].strip
        return [] if inner.empty?

        split_array(inner).map { |item| parse_value(item.strip) }
      elsif value.match?(/\A-?\d+\z/)
        value.to_i
      else
        value
      end
    end

    def self.split_array(inner)
      parts = []
      current = +""
      in_string = false
      inner.each_char do |char|
        if char == '"'
          in_string = !in_string
          current << char
        elsif char == "," && !in_string
          parts << current
          current = +""
        else
          current << char
        end
      end
      parts << current unless current.empty?
      parts
    end
  end

  class ConfigGuard
    attr_reader :store

    def initialize(store)
      @store = store
    end

    def ensure_config
      store.write(".codex/config.toml", SimpleToml.dump(CONFIG_DEFAULTS)) unless store.exist?(".codex/config.toml")
      store.write(".codex/config.defaults.toml", config_defaults_toml) unless store.exist?(".codex/config.defaults.toml")
      validate
    end

    def validate
      config = SimpleToml.parse(store.read(".codex/config.toml"))
      errors = []
      warnings = []

      CONFIG_SCHEMA.each do |key, spec|
        if spec[:required] && !config.key?(key)
          errors << "missing required key: #{key}"
          next
        end
        next unless config.key?(key)

        value = config[key]
        errors.concat(validate_type(key, value, spec))
      end

      unknown = config.keys - CONFIG_SCHEMA.keys
      unknown.each { |key| warnings << "unknown key: #{key}" }

      { ok: errors.empty?, config: config, errors: errors, warnings: warnings }
    end

    def validate_aliases
      config = validate[:config]
      aliases = config["technical_area_aliases"]
      return { ok: true, aliases: aliases, stopped_processing: [] } if aliases.empty?

      invalid = aliases.reject { |item| item.is_a?(Hash) && item["from"].is_a?(String) && item["to"].is_a?(String) }
      return { ok: true, aliases: aliases, stopped_processing: [] } if invalid.empty?

      {
        ok: false,
        error: "technical_area_aliases format error",
        stopped_processing: ["alias_analysis"],
        continue_processing: ["normal_answer", "term_management", "learning_log"],
        repair_suggestion: "[[technical_area_aliases]]\nfrom = \"Validation\"\nto = \"FormRequest\"\n"
      }
    end

    def validate_type(key, value, spec)
      errors = []
      type_ok = case spec[:type]
                when :string then value.is_a?(String)
                when :integer then value.is_a?(Integer)
                when :string_array then value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
                when :integer_array then value.is_a?(Array) && value.all? { |item| item.is_a?(Integer) }
                when :alias_array then value.is_a?(Array) && value.all? { |item| item.is_a?(Hash) }
                else true
                end
      errors << "#{key}: invalid type" unless type_ok
      return errors unless type_ok

      errors << "#{key}: value not allowed" if spec[:allowed] && !spec[:allowed].include?(value)
      if value.is_a?(Array) && spec[:allowed_items]
        bad = value - spec[:allowed_items]
        errors << "#{key}: invalid items #{bad.join(", ")}" unless bad.empty?
      end
      errors << "#{key}: below min" if spec[:min] && value.is_a?(Integer) && value < spec[:min]
      errors << "#{key}: above max" if spec[:max] && value.is_a?(Integer) && value > spec[:max]
      if value.is_a?(Array) && spec[:min_item]
        errors << "#{key}: item below min" if value.any? { |item| item.is_a?(Integer) && item < spec[:min_item] }
      end
      if value.is_a?(Array) && spec[:max_item]
        errors << "#{key}: item above max" if value.any? { |item| item.is_a?(Integer) && item > spec[:max_item] }
      end
      errors
    end

    def config_defaults_toml
      lines = ["template_version = \"1.0\""]
      CONFIG_SCHEMA.each do |key, spec|
        lines << ""
        lines << "[[settings]]"
        lines << "key = #{key.inspect}"
        lines << "required = #{spec[:required] ? "true" : "false"}"
        lines << "type = #{spec[:type].to_s.inspect}"
      end
      lines.join("\n") + "\n"
    end
  end

  class Classifier
    ERROR_PATTERNS = [/error/i, /exception/i, /undefined method/i, /not found/i, /SQLSTATE/i, /失敗/, /エラー/, /動かない/, /404/].freeze
    ASSESS_PATTERNS = [/問題ありませんか/, /合っていますか/, /十分ですか/, /評価/, /実務/, /面接/].freeze
    FEATURE_PATTERNS = [/Route.*Controller/i, /Controller.*Blade/i, /つなが/, /流れ/, /全体/, /複数/, /ファイル/, /DB保存/, /画面遷移/].freeze

    def classify(input)
      text = input.to_s
      if ERROR_PATTERNS.any? { |pattern| text.match?(pattern) }
        return result("error", "エラーまたは失敗の原因と確認順序を知りたい質問であるため。", "high")
      end
      if ASSESS_PATTERNS.any? { |pattern| text.match?(pattern) }
        return result("assess", "作成したコード、説明、設計、テスト、理解内容の評価を求めているため。", "high")
      end
      if FEATURE_PATTERNS.any? { |pattern| text.match?(pattern) }
        return result("feature", "複数のコード、ファイル、処理やデータの流れを理解したい質問であるため。", "high")
      end

      result("unit", "コード一文、関数、メソッド、API、構文の意味を確認する質問であるため。", "medium")
    end

    def result(classification, reason, confidence)
      raise "invalid classification: #{classification}" unless VALID_CLASSIFICATIONS.include?(classification)

      {
        classification: classification,
        reason: reason,
        confidence: confidence,
        missing_info: [],
        need_user_confirmation: false,
        assumption: nil
      }
    end
  end

  class ScopeReader
    PATH_PATTERN = %r{([A-Za-z0-9_\-./]+)\.(php|rb|js|ts|blade\.php|md|toml)|resources/|app/|routes/|tests/}
    SECRET_PATTERN = /(API_KEY|SECRET|TOKEN|PASSWORD|BEGIN RSA PRIVATE KEY|\.env)/i

    def check(input, classification)
      text = input.to_s
      if text.match?(SECRET_PATTERN)
        return {
          allowed: false,
          reason: "秘密情報の可能性があるため、内容を表示せず参照を止める。",
          allowed_scope: [],
          need_user_confirmation: true
        }
      end

      return allowed(["chat"]) if pasted_code?(text) || text.match?(PATH_PATTERN)

      if classification == "feature"
        return {
          allowed: false,
          reason: "参照範囲が未確定で、コード閲覧前に確認が必要なため。",
          allowed_scope: ["chat"],
          need_user_confirmation: true,
          confirmation_message: "関連するRoute、Controller、Bladeなど、参照してよい範囲を指定してください。"
        }
      end

      allowed(["chat"])
    end

    def pasted_code?(text)
      text.include?("```") || text.lines.count > 1 || text.include?("->") || text.include?("function")
    end

    def allowed(scope)
      { allowed: true, reason: "学習者が提示したチャット本文を参照できる。", allowed_scope: scope, need_user_confirmation: false }
    end
  end

  class AnswerBuilder
    def build(input, classification_result)
      classification = classification_result[:classification]
      reason = classification_result[:reason]
      case classification
      when "feature"
        feature(input, reason)
      when "unit"
        unit(input, reason)
      when "assess"
        assess(input, reason)
      when "error"
        error(input, reason)
      else
        unit(input, reason)
      end
    end

    def feature(input, reason)
      <<~MD
        # 分類
        分類: feature
        分類理由: #{reason}

        # 今回の学習テーマ
        複数ファイルや処理のつながりを、入口、処理、出力に分けて確認すること。

        # つまずきの中核
        1つのコードだけではなく、Route、Controller、View、JavaScript、DBなどの役割を分けて読めていない可能性がある。

        # 全体像
        機能全体は、入口、処理、出力の順に見ると整理しやすい。

        # 理解ステップ
        1. 入口を確認する。
        2. 処理を担当するファイルを確認する。
        3. データがどこで作られ、どこへ渡るかを見る。
        4. 最後に画面表示、DB保存、API応答などの終点を見る。

        # 具体例（他でも使える考え方）
        登録、編集、一覧、詳細のような機能でも、入口、処理、出力の順に確認できる。

        # 次に同じ問題が出たら見る順番
        1. Routeまたは呼び出し元
        2. Controllerまたは処理担当
        3. Model、DB、APIなどのデータ処理
        4. Bladeや画面表示

        # 理解確認
        この機能で、最初に「入口」として確認する場所はどこになりそうですか。
      MD
    end

    def unit(input, reason)
      target = input.to_s.strip
      <<~MD
        # 分類
        分類: unit
        分類理由: #{reason}

        # 今回の学習テーマ
        コード一文やメソッドを、小さな部品に分解して読むこと。

        # つまずきの中核
        コード全体を一気に読もうとして、左側の値、呼び出すメソッド、引数、結果を分けられていない可能性がある。

        # 全体像
        対象: `#{target}`

        # 理解ステップ
        1. 左側の値が何かを見る。
        2. 呼び出しているメソッドや関数を見る。
        3. 引数として渡している値を見る。
        4. 戻り値や副作用を確認する。

        # 具体例（他でも使える考え方）
        `親->関係()->作成()`、`要素.値.加工()` のように、つながったコードは左から順に読む。

        # 次に同じ問題が出たら見る順番
        1. 変数
        2. メソッド
        3. 引数
        4. 結果

        # 理解確認
        この一文の中で、最初に確認するべき変数や値はどれですか。
      MD
    end

    def assess(input, reason)
      <<~MD
        # 分類
        分類: assess
        分類理由: #{reason}

        # 現状の確認
        評価対象の内容を確認し、合っている点、不足している点、改善できる点を分けて見る。

        # 評価
        具体的なコードや説明がある場合は、その内容を根拠に評価する。対象が未提示の場合は、回答前に提示を求める。

        # つまずき（assess）の中核
        正しいかどうかだけではなく、なぜその書き方でよいのか、どの条件なら不足するのかを確認する必要がある。

        # 全体像
        評価では、目的、入力、処理、出力、検証方法の順に見る。

        # 理解ステップ
        1. 何を実現したいかを見る。
        2. そのコードが目的を満たすかを見る。
        3. 足りない条件や例外を確認する。
        4. テストや画面確認で検証できるかを見る。

        # 改善案
        評価対象を提示すると、良い点、問題点、実務上の注意を分けて具体化できる。

        # 具体例（他でも使える考え方）
        validation、設計、テストは、目的と確認条件を分けると評価しやすい。

        # 次に同じ問題が出たら見る順番
        1. 目的
        2. 実装内容
        3. 足りない条件
        4. 検証方法

        # 理解確認
        評価してほしい内容は、目的、コード、テストのどれに一番近いですか。
      MD
    end

    def error(input, reason)
      <<~MD
        # 分類
        分類: error
        分類理由: #{reason}

        # エラーの意味
        エラー文は、実行中に期待した処理が見つからない、条件を満たさない、または環境が揃っていないことを示している可能性がある。

        # 発生している場所
        エラー文に含まれるModel、Controller、Route、SQL、ファイル名、メソッド名を起点に確認する。

        # 現時点で分かっていること
        提示されたエラー文から分かることだけを確定情報として扱う。

        # つまずき（error）の中核
        原因をすぐ断定せず、エラー文から確認順序を作る必要がある。

        # 全体像
        エラー対応は、意味、場所、原因仮説、確認順序、修正、検証の順に進める。

        # 原因仮説
        1. 呼び出しているメソッドやファイルが存在しない。
        2. 名前やパスが違う。
        3. migration、依存関係、キャッシュなど環境側が揃っていない。

        # 確認する順番
        1. エラー文の対象名を見る。
        2. 対象ファイルやメソッドが存在するか確認する。
        3. 呼び出し元と定義側の名前が一致するか確認する。
        4. 修正後に同じ操作を再実行する。

        # 理解ステップ
        エラー文は、まず「何が」「どこで」「どう見つからないか」に分けて読む。

        # 修正案
        確認結果に応じて、定義追加、名前修正、パス修正、migration実行、キャッシュクリアなどを選ぶ。

        # 検証方法
        同じ操作をもう一度行い、同じエラーが消えるか確認する。

        # 具体例（他でも使える考え方）
        `undefined method` は定義確認、`404` はRoute確認、`SQLSTATE` はDBとmigration確認から始める。

        # 次に同じ問題が出たら見る順番
        1. エラー文
        2. 対象名
        3. 定義場所
        4. 呼び出し元
        5. 検証

        # 理解確認
        このエラー文で、まず確認する対象名はどれですか。
      MD
    end
  end

  class TermManager
    attr_reader :store

    def initialize(store)
      @store = store
    end

    def today
      ENV["PROGRAMMING_AI_DATE"] || Date.today.strftime("%Y-%m-%d")
    end

    def create_term(question, classification_result, scope_result)
      intent = input_intent(question)
      unless intent == "learning_question"
        return { created: false, reason: "#{intent}であり学習タームではない。", awaiting: "none" }
      end

      date = today
      sequence = next_sequence(date)
      slug = topic_slug(question, classification_result[:classification])
      term_id = "#{date}-#{sequence}-#{slug}"
      dir = ".codex/state/terms/#{date}/#{sequence}-#{slug}"
      case_path = "learning-cases/#{date}.md"
      now = timestamp
      status = scope_result[:allowed] ? "understanding_check" : "awaiting_scope"
      awaiting = scope_result[:allowed] ? "understanding_answer" : "scope_confirmation"
      answer_body = scope_result[:allowed] ? AnswerBuilder.new.build(question, classification_result) : ""

      store.write("#{dir}/question.md", "# 質問\n\n#{question}\n")
      store.write("#{dir}/context.md", "# 参照範囲\n\n#{scope_result[:allowed_scope].map { |item| "- #{item}" }.join("\n")}\n")
      store.write("#{dir}/answer-draft.md", answer_body)
      store.write("#{dir}/log-draft.md", "# ログ化判断\n\n未判断\n")
      store.write("#{dir}/metadata.toml", metadata_toml(term_id, date, sequence, slug, classification_result, status, awaiting, "none", now, case_path))
      append_learning_case(date, sequence, slug, term_id, question, classification_result, scope_result, status, answer_body, now)
      store.write(".codex/state/current-term.toml", current_term_toml(true, term_id, dir, classification_result[:classification], status, awaiting, now))

      { created: true, term_id: term_id, term_path: dir, case_path: case_path, status: status, awaiting: awaiting }
    end

    def current_term
      return nil unless store.exist?(".codex/state/current-term.toml")

      state = SimpleToml.parse(store.read(".codex/state/current-term.toml"))
      return nil unless state["active"] == true && state["term_id"]
      return nil if state["status"] == "paused"

      state
    end

    def current_term_id
      current_term&.fetch("term_id", nil)
    end

    def new_topic?(question, classification_result)
      state = current_term
      return false unless state

      term = find_term(state["term_id"])
      return false unless term

      metadata = SimpleToml.parse(File.read(store.path(term, "metadata.toml")))
      topic_slug(question, classification_result[:classification]) != metadata["topic_slug"]
    end

    def mark_term_boundary(term_id, trigger:, reason:)
      term = find_term(term_id)
      raise "term not found: #{term_id}" unless term

      metadata = SimpleToml.parse(File.read(store.path(term, "metadata.toml")))
      metadata["status"] = "log_decision"
      metadata["awaiting"] = "log_decision"
      metadata["term_boundary_trigger"] = trigger
      metadata["term_boundary_reason"] = reason
      metadata["updated_at"] = timestamp
      store.write("#{term}/metadata.toml", SimpleToml.dump(metadata))
      store.write(".codex/state/current-term.toml", current_term_toml(true, term_id, term, metadata["classification"], "log_decision", "log_decision", timestamp))

      {
        term_boundary_candidate: true,
        term_id: term_id,
        trigger: trigger,
        reason: reason,
        status: "log_decision",
        awaiting: "log_decision"
      }
    end

    def complete_understanding(term_id, answer)
      term = find_term(term_id)
      raise "term not found: #{term_id}" unless term

      answer_path = store.path(term, "answer-draft.md")
      current_answer = File.read(answer_path)
      unless current_answer.include?("# 理解確認への返答")
        store.write(answer_path, "#{current_answer.rstrip}\n\n# 理解確認への返答\n\n#{answer}\n")
      end

      mark_term_boundary(
        term_id,
        trigger: "understanding_answer",
        reason: "理解確認への返答を受けたため。"
      )
    end

    def input_intent(text)
      return "config" if text.match?(/config|設定|参照範囲設定/)
      return "mentor_command" if text.strip == "学習開始"
      return "casual" if text.strip.match?(/\A(こんにちは|ありがとう|了解|はい|いいえ)\z/)
      return "save_decline" if text.match?(/保存(?:しない|しません|不要)|ログ化(?:しない|しません|不要)/)
      return "save_permission" if text.strip.match?(/\A(?:保存(?:する|して|してよい|して大丈夫)|保存許可)\z/)
      return "log_revision" if text.include?("修正完了")
      return "log_request" if text.match?(/内容をまとめ|まとめてほしい|学習ログ.*(?:まとめ|残)|ログ化(?:したい|する|して)/)

      "learning_question"
    end

    def next_sequence(date)
      entries = store.list(".codex/state/terms/#{date}")
      max = entries.map { |entry| entry[/\A(\d{3})-/, 1] }.compact.map(&:to_i).max.to_i
      format("%03d", max + 1)
    end

    def topic_slug(question, classification)
      text = question.downcase
      return "fetch-controller-flow" if text.match?(/fetch/)
      return "route-controller-blade-flow" if text.match?(/route|controller|blade|ログイン/)
      return "validation-rule-check" if text.match?(/validation|バリデーション/)

      "#{classification}-learning"
    end

    def pause(term_id, reason = "学習者が別テーマへ移ったため")
      term = find_term(term_id)
      return nil unless term

      metadata = SimpleToml.parse(File.read(store.path(term, "metadata.toml")))
      metadata["status"] = "paused"
      metadata["awaiting"] = "resume_choice"
      metadata["updated_at"] = timestamp
      store.write("#{term}/metadata.toml", SimpleToml.dump(metadata))
      store.write(".codex/state/paused-terms.toml", paused_terms_toml(term_id, term, metadata["classification"], reason))
      store.write(".codex/state/current-term.toml", current_term_toml(true, term_id, term, metadata["classification"], "paused", "resume_choice", timestamp))
      { paused: true, term_path: term }
    end

    def resume(term_id)
      term = find_term(term_id)
      return nil unless term

      metadata = SimpleToml.parse(File.read(store.path(term, "metadata.toml")))
      metadata["status"] = "understanding_check"
      metadata["awaiting"] = "understanding_answer"
      metadata["updated_at"] = timestamp
      store.write("#{term}/metadata.toml", SimpleToml.dump(metadata))
      store.write(".codex/state/paused-terms.toml", "paused_terms = []\n")
      store.write(".codex/state/current-term.toml", current_term_toml(true, term_id, term, metadata["classification"], "understanding_check", "understanding_answer", timestamp))
      answer = File.read(store.path(term, "answer-draft.md"))
      unless answer.include?("# 再開後の回答")
        store.write("#{term}/answer-draft.md", answer + "\n# 再開後の回答\n\n保留していた学習タームを再開しました。\n\n# 理解確認\n\n前回の続きとして、次に確認する場所はどこですか。\n")
      end
      { resumed: true, term_path: term }
    end

    def find_term(term_id)
      Dir.glob(store.path(".codex/state/terms", "*", "*")).find do |dir|
        File.directory?(dir) && File.exist?(File.join(dir, "metadata.toml")) &&
          SimpleToml.parse(File.read(File.join(dir, "metadata.toml")))["term_id"] == term_id
      end&.then { |full| full.sub("#{store.root}/", "") }
    end

    def metadata_toml(term_id, date, sequence, slug, classification_result, status, awaiting, log_status, time, case_path)
      SimpleToml.dump(
        "term_id" => term_id,
        "date" => date,
        "sequence" => sequence.to_i,
        "topic_slug" => slug,
        "case_path" => case_path,
        "log_path" => "none",
        "classification" => classification_result[:classification],
        "classification_reason" => classification_result[:reason],
        "confidence" => classification_result[:confidence],
        "status" => status,
        "awaiting" => awaiting,
        "log_status" => log_status,
        "log_trigger" => "none",
        "save_permission" => "not_requested",
        "light_memo_status" => "none",
        "light_memo_source" => "none",
        "referenced_scope" => ["chat"],
        "created_at" => time,
        "updated_at" => time
      )
    end

    def append_learning_case(date, sequence, slug, term_id, question, classification_result, scope_result, status, answer_body, time)
      relative = "learning-cases/#{date}.md"
      body = store.exist?(relative) ? store.read(relative) : learning_case_header(date)
      marker = "term_id: #{term_id}"
      return if body.include?(marker)

      scope_text = scope_result[:allowed_scope].map { |item| "- #{item}" }.join("\n")
      scope_text = "- 未確定" if scope_text.empty?
      body += <<~MD

        ---

        ## #{sequence}. #{topic_title_from_slug(slug)}

        ### 記録情報

        - term_id: #{term_id}
        - 時刻: #{time}
        - 質問分類: #{classification_result[:classification]}
        - 参照範囲:
        #{indent_lines(scope_text, 2)}
        - 状態: #{status}

        ### 質問した内容

        #{question}

        ### つまずきの中核

        #{case_stumble_core(classification_result[:classification], status)}

        ### 回答の要点

        #{case_answer_summary(classification_result[:classification], status, answer_body)}

        ### 学んだ内容

        #{case_learned_summary(classification_result[:classification], status)}

        ### 確認したこと

        - 回答または回答前確認の状態を記録した。

        ### 苦手傾向の根拠候補

        - 苦手種類: #{case_weakness_type(classification_result[:classification])}
        - 技術領域: #{case_technical_area(slug)}
        - 根拠として使える内容: #{case_evidence_summary(classification_result[:classification], status)}

        ### 次に同じ問題が出たら見る順番

        1. 入口
        2. 処理
        3. 出力
        4. 検証方法

        ### 関連する確定学習ログ

        - なし
      MD
      store.write(relative, body)
    end

    def learning_case_header(date)
      <<~MD
        # #{date} Learning Case

        ## この日の学習概要

        - 記録対象: プログラミング学習の質問のみ
        - 記録単位: 質問全文 + 回答要点 + 学習根拠
        - 最終更新: #{timestamp}
      MD
    end

    def topic_title_from_slug(slug)
      case slug
      when /route-controller-blade/
        "Route、Controller、Bladeのつながり"
      when /validation/
        "Validationの書き方確認"
      when /fetch/
        "FetchからControllerへの流れ"
      else
        slug
      end
    end

    def indent_lines(text, spaces)
      padding = " " * spaces
      text.lines.map { |line| "#{padding}#{line}" }.join.rstrip
    end

    def case_stumble_core(classification, status)
      return "参照範囲が未確定で、回答前に確認が必要な状態。" if status == "awaiting_scope"

      case classification
      when "feature"
        "複数ファイルの役割や処理の流れを、入口、処理、出力に分けて読めていない可能性がある。"
      when "unit"
        "コード一文を、値、メソッド、引数、結果に分解して読めていない可能性がある。"
      when "assess"
        "正誤だけでなく、判断根拠と改善点を分けて確認する必要がある。"
      when "error"
        "エラー文、発生場所、原因仮説、確認順序を分けて整理する必要がある。"
      else
        "学習内容の整理が必要な状態。"
      end
    end

    def case_answer_summary(classification, status, answer_body)
      return "回答前確認中。参照範囲が確定したら説明を進める。" if status == "awaiting_scope"
      return "回答を作成した。分類に応じた型で、考え方と確認順序を優先して説明した。" if answer_body.empty?

      case classification
      when "feature"
        "機能全体を、入口、処理、データの流れ、出力の順に確認する。"
      when "unit"
        "コードを左から順に、値、呼び出し、引数、結果へ分解する。"
      when "assess"
        "目的、入力、処理、出力、検証方法を分けて評価する。"
      when "error"
        "エラーの意味、発生場所、原因仮説、確認順序、修正案、検証方法を分ける。"
      else
        "考え方と確認順序を整理した。"
      end
    end

    def case_learned_summary(classification, status)
      return "回答に必要な参照範囲を明示する必要がある。" if status == "awaiting_scope"

      case classification
      when "feature"
        "複数ファイルの関係は、役割と流れに分けると理解しやすい。"
      when "unit"
        "一文のコードは、小さな部品へ分けて読むと再現しやすい。"
      when "assess"
        "評価では、合っている点、不足、改善点を分ける。"
      when "error"
        "エラー対応では、すぐ修正せず確認順序から原因を絞る。"
      else
        "学習内容を再利用できる考え方として整理した。"
      end
    end

    def case_weakness_type(classification)
      case classification
      when "feature"
        "構造理解"
      when "unit", "error"
        "技術知識"
      when "assess"
        "思考プロセス"
      else
        "未分類"
      end
    end

    def case_technical_area(slug)
      return "Laravel / Route / Controller / Blade" if slug.match?(/route-controller-blade/)
      return "Validation" if slug.match?(/validation/)
      return "JavaScript / Fetch / Controller" if slug.match?(/fetch/)

      "未分類"
    end

    def case_evidence_summary(classification, status)
      return "参照範囲の指定が不足しており、回答前確認が必要だった。" if status == "awaiting_scope"

      case classification
      when "feature"
        "ファイルや処理のつながりを確認する質問だった。"
      when "unit"
        "コード一文または関数の意味を確認する質問だった。"
      when "assess"
        "自分の理解や実装を評価してほしい質問だった。"
      when "error"
        "エラーの原因と確認順序を整理する質問だった。"
      else
        "プログラミング学習に関する質問だった。"
      end
    end

    def current_term_toml(active, term_id, term_path, classification, status, awaiting, time)
      SimpleToml.dump(
        "active" => active,
        "term_id" => term_id,
        "term_path" => term_path,
        "classification" => classification,
        "status" => status,
        "awaiting" => awaiting,
        "referenced_scope" => ["chat"],
        "last_user_intent" => status,
        "updated_at" => time
      )
    end

    def paused_terms_toml(term_id, term_path, classification, reason)
      <<~TOML
        [[paused_terms]]
        term_id = "#{term_id}"
        term_path = "#{term_path}"
        classification = "#{classification}"
        status = "paused"
        paused_reason = "#{reason}"
        paused_at = "#{timestamp}"
        resume_hint = "前回の理解確認から再開"
      TOML
    end

    def timestamp
      Time.now.getlocal("+09:00").iso8601
    end
  end

  class MentorMemory
    MEMORY_PATH = ".codex/agents/mentor/MEMORY.md"
    CONFIDENCE_ORDER = { "高" => 0, "中" => 1, "低" => 2 }.freeze
    WEAKNESS_ORDER = { "技術知識" => 0, "構造理解" => 1, "思考プロセス" => 2 }.freeze

    attr_reader :store

    def initialize(store)
      @store = store
    end

    def refresh!(source: "analysis")
      candidates = extract_candidates
      groups = group_candidates(candidates)
      store.write(MEMORY_PATH, memory_body(groups, source))
      {
        memory_path: MEMORY_PATH,
        candidates: candidates.size,
        weakness_entries: groups.size,
        source: source
      }
    end

    def records
      return [] unless store.exist?(MEMORY_PATH)

      body = store.read(MEMORY_PATH)
      body.scan(/^### \d+\. (.+?)\n(.*?)(?=^### \d+\. |\z)/m).map do |title, block|
        {
          title: title.strip,
          date: record_field(block, "日付"),
          classification: record_field(block, "分類"),
          stumble: record_field(block, "つまずき"),
          technical_area: record_field(block, "技術領域"),
          weakness_type: record_field(block, "苦手種類"),
          confidence: record_field(block, "確信度"),
          count: record_field(block, "出現回数").to_i,
          evidence: record_evidence(block)
        }
      end
    end

    def display_records
      records
        .select { |record| %w[高 中].include?(record[:confidence]) }
        .sort_by { |record| record_sort_key(record) }
    end

    def primary_record
      display_records.first
    end

    private

    def extract_candidates
      candidates_from_cases + candidates_from_logs
    end

    def candidates_from_cases
      Dir.glob(store.path("learning-cases", "*.md")).sort.flat_map do |path|
        date = File.basename(path, ".md")
        body = File.read(path)
        body.split(/^## /).drop(1).map do |block_body|
          block = "## #{block_body}"
          build_candidate(block, "learning-cases/#{File.basename(path)}", date)
        end.compact
      end
    end

    def candidates_from_logs
      Dir.glob(store.path("learning-logs", "*.md")).sort.map do |path|
        file_name = File.basename(path)
        date = file_name[/\A\d{4}-\d{2}-\d{2}/] || "unknown"
        build_candidate(File.read(path), "learning-logs/#{file_name}", date)
      end.compact
    end

    def build_candidate(text, source_path, date)
      classification = extract_classification(text)
      stumble = extract_stumble(text)
      return nil unless classification || stumble

      technical_area = extract_inline_field(text, "技術領域") || infer_technical_area(text)
      weakness_type = extract_inline_field(text, "苦手種類") || infer_weakness_type(classification, text)
      {
        date: date,
        classification: classification || "未分類",
        stumble: compact_text(stumble || title_from_text(text) || "学習内容の理解が未整理。"),
        technical_area: technical_area,
        weakness_type: weakness_type,
        source_path: source_path
      }
    end

    def group_candidates(candidates)
      grouped = {}
      candidates.each do |candidate|
        key = [candidate[:technical_area], candidate[:weakness_type]]
        grouped[key] ||= {
          dates: [],
          classifications: [],
          stumbles: [],
          technical_area: candidate[:technical_area],
          weakness_type: candidate[:weakness_type],
          evidence: [],
          count: 0
        }
        grouped[key][:dates] << candidate[:date]
        grouped[key][:classifications] << candidate[:classification]
        grouped[key][:stumbles] << candidate[:stumble]
        grouped[key][:evidence] << candidate[:source_path]
        grouped[key][:count] += 1
      end
      grouped.values.map do |group|
        group[:dates] = group[:dates].uniq.sort
        group[:classifications] = group[:classifications].uniq.sort
        group[:stumbles] = group[:stumbles].uniq.sort_by { |stumble| stumble_sort_key(stumble) }
        group[:evidence] = group[:evidence].uniq
        group[:confidence] = confidence_for(group[:count])
        group
      end.sort_by { |group| group_sort_key(group) }
    end

    def memory_body(groups, source)
      entries = groups.each_with_index.map do |group, index|
        evidence = group[:evidence].first(3).map { |path| "  - #{path}" }.join("\n")
        <<~MD
          ### #{format("%03d", index + 1)}. #{group[:technical_area]} / #{group[:weakness_type]}

          - 日付: #{group[:dates].join(", ")}
          - 分類: #{group[:classifications].join(", ")}
          - つまずき: #{group[:stumbles].first}
          - 技術領域: #{group[:technical_area]}
          - 苦手種類: #{group[:weakness_type]}
          - 確信度: #{group[:confidence]}
          - 出現回数: #{group[:count]}
          - 根拠ログ:
          #{evidence}
        MD
      end
      entries = ["候補なし\n"] if entries.empty?
      <<~MD
        # Mentor MEMORY

        mentor Agent専用の苦手分析メモリ。
        Codex全体のMemoryではなく、このProject内のmentor専用MEMORYとして扱う。

        ## 更新情報

        - 最終分析: #{Time.now.getlocal("+09:00").iso8601}
        - 更新理由: #{source}
        - 読み取り元: learning-cases / learning-logs
        - 表示ルール: 通常表示では確信度の値を出さず、中または高の苦手だけを優先する。

        ## 苦手分析ログ

        #{entries.join("\n")}
      MD
    end

    def record_sort_key(record)
      [
        CONFIDENCE_ORDER.fetch(record[:confidence], 9),
        WEAKNESS_ORDER.fetch(record[:weakness_type], 9),
        -record[:count],
        record[:technical_area].to_s
      ]
    end

    def group_sort_key(group)
      [
        CONFIDENCE_ORDER.fetch(group[:confidence], 9),
        WEAKNESS_ORDER.fetch(group[:weakness_type], 9),
        -group[:count],
        group[:technical_area]
      ]
    end

    def confidence_for(count)
      return "高" if count >= 3
      return "中" if count == 2

      "低"
    end

    def extract_classification(text)
      raw = extract_inline_field(text, "質問分類") ||
        extract_inline_field(text, "分類") ||
        extract_heading_value(text, "質問分類")
      normalize_classification(raw, text)
    end

    def normalize_classification(raw, text)
      value = raw.to_s.strip
      return value if VALID_CLASSIFICATIONS.include?(value)

      infer_classification_from_text(text)
    end

    def infer_classification_from_text(text)
      return "error" if text.match?(/エラー|exception|undefined method|SQLSTATE|失敗|動かない/i)
      return "assess" if text.match?(/合って|問題ありませんか|十分|評価|判断/)
      return "feature" if text.match?(/全体|流れ|つなが|役割分担|紐づ|リレーション|Factory|setUp|makeValidator|ランキング処理/)

      "unit"
    end

    def extract_stumble(text)
      extract_inline_field(text, "つまずき") ||
        extract_inline_field(text, "つまずきの中核") ||
        extract_heading_value(text, "つまずきの中核")
    end

    def extract_inline_field(text, label)
      match = text.match(/^\s*-\s*#{Regexp.escape(label)}:\s*(.+)$/)
      match && compact_text(match[1])
    end

    def extract_heading_value(text, heading)
      lines = text.lines
      index = lines.index { |line| line.strip == "# #{heading}" || line.strip == "### #{heading}" }
      return nil unless index

      collected = []
      lines[(index + 1)..].to_a.each do |line|
        break if line.start_with?("#")
        break if heading == "つまずきの中核" && line.strip == "Agentの見立て:"

        collected << line
      end
      compact_text(collected.join)
    end

    def title_from_text(text)
      text.lines.find { |line| line.start_with?("# ") || line.start_with?("## ") }&.sub(/\A#+\s*/, "")
    end

    def infer_technical_area(text)
      return "PHPUnit / Data Provider" if text.match?(/PHPUnit|dataProvider|データプロバイダー|Provider/)
      return "Laravel / Eloquent / Relation" if text.match?(/Factory|reviews\(\)|Book \$book|attach\(|リレーション|紐づ/)
      return "PHP / Closure" if text.match?(/クロージャ|closure|use \(&|use \(\$/i)
      return "Laravel / Validation / FormRequest" if text.match?(/Validator|FormRequest|UpdateBookRequest|rules\(\)|messages\(\)|Validation|バリデーション/)
      return "Laravel / Route / Controller / Blade" if text.match?(/Route|Controller|Blade|view\(\)/)
      return "JavaScript / Fetch / Controller" if text.match?(/fetch/i)

      "未分類"
    end

    def infer_weakness_type(classification, text)
      return "思考プロセス" if classification == "assess" && text.match?(/判断|評価|十分|合って/)
      return "構造理解" if text.match?(/Factory|attach\(|reviews\(\)|Book \$book|ルートモデルバインディング|役割分担|結びつき|紐づ/)
      return "技術知識" if text.match?(/dataProvider|データプロバイダー|use \(&|use \(\$|Validator::make|rules\(\)|messages\(\)|クロージャ/i)
      return "構造理解" if classification == "feature"
      return "技術知識" if %w[unit error].include?(classification)
      return "構造理解" if text.match?(/つなが|リレーション|setUp|makeValidator|Route|Controller|Blade/)
      return "思考プロセス" if text.match?(/判断|評価|使い分け|十分|合って/)

      "技術知識"
    end

    def stumble_sort_key(stumble)
      text = stumble.to_s
      score = 0
      score += 20 if text.include?("既存の学習ターム")
      score += 10 if text.include?("学習内容の理解が未整理")
      score += 4 if text.length > 180
      score -= 5 if text.match?(/分から|曖昧|役割分担|つまず|どこから/)
      score
    end

    def compact_text(text)
      text.to_s
        .gsub(/```.*?```/m, "")
        .gsub(/^\s*[-*]\s*/, "")
        .gsub(/\s+/, " ")
        .strip[0, 220]
    end

    def record_field(block, label)
      match = block.match(/^\s*-\s*#{Regexp.escape(label)}:\s*(.+)$/)
      match ? match[1].strip : ""
    end

    def record_evidence(block)
      match = block.match(/^\s*-\s*根拠ログ:\n((?:\s{2}-\s*.+\n?)+)/)
      return [] unless match

      match[1].lines.map { |line| line.sub(/^\s*-\s*/, "").strip }.reject(&:empty?)
    end
  end

  class LogWorkflow
    attr_reader :store, :term_manager

    def initialize(store, term_manager)
      @store = store
      @term_manager = term_manager
    end

    def create_log_draft(term_id, trigger: "term_boundary")
      term = term_manager.find_term(term_id)
      raise "term not found: #{term_id}" unless term

      metadata = SimpleToml.parse(File.read(store.path(term, "metadata.toml")))
      question = File.read(store.path(term, "question.md")).sub("# 質問", "").strip
      classification = metadata["classification"]
      topic = topic_title(metadata)
      body = learning_log(topic, classification, question)
      store.write("#{term}/log-draft.md", body)
      metadata["status"] = "log_draft_created"
      metadata["awaiting"] = "save_permission"
      metadata["log_status"] = "draft"
      metadata["log_trigger"] = trigger
      metadata["save_permission"] = "pending"
      metadata["light_memo_status"] = "none"
      metadata["light_memo_source"] = "none"
      metadata["updated_at"] = Time.now.getlocal("+09:00").iso8601
      store.write("#{term}/metadata.toml", SimpleToml.dump(metadata))
      {
        log_draft_created: true,
        term_path: term,
        trigger: trigger,
        awaiting: "save_permission",
        save_permission: "pending",
        save_prompt: "この学習ログ候補を保存してよいですか？"
      }
    end

    def save_log(term_id)
      term = term_manager.find_term(term_id)
      raise "term not found: #{term_id}" unless term

      metadata = SimpleToml.parse(File.read(store.path(term, "metadata.toml")))
      unless metadata["log_status"] == "draft" && metadata["awaiting"] == "save_permission"
        raise "save permission is not pending: #{term_id}"
      end

      date = metadata["date"]
      file_name = "#{date}-#{format("%03d", metadata["sequence"])}-#{metadata["topic_slug"]}.md"
      log_path = "learning-logs/#{file_name}"
      body = File.read(store.path(term, "log-draft.md"))
      store.write(log_path, body)
      update_learner_profile(log_path, metadata)
      update_memory(metadata)
      metadata["status"] = "log_saved"
      metadata["awaiting"] = "none"
      metadata["log_status"] = "saved"
      metadata["log_path"] = log_path
      metadata["save_permission"] = "granted"
      metadata["light_memo_status"] = "none"
      metadata["light_memo_source"] = "none"
      append_case_status(metadata, "確定学習ログ: #{log_path}")
      store.write("#{term}/metadata.toml", SimpleToml.dump(metadata))
      mentor_memory = MentorMemory.new(store).refresh!(source: "confirmed_log_save")
      store.write(".codex/state/current-term.toml", term_manager.current_term_toml(false, term_id, term, metadata["classification"], "log_saved", "none", Time.now.getlocal("+09:00").iso8601))
      { saved: true, log_path: log_path, mentor_memory: mentor_memory }
    end

    def no_log(term_id, reason)
      term = term_manager.find_term(term_id)
      raise "term not found: #{term_id}" unless term

      metadata = SimpleToml.parse(File.read(store.path(term, "metadata.toml")))
      memo = <<~MD
        # ログ化判断

        ログ化しない。

        # 理由

        #{reason}

        # 軽量メモ候補

        - 分類: #{metadata["classification"]}
        - テーマ: #{topic_title(metadata)}
        - つまずき候補: 学習内容がまだ具体化していない
        - 参照した範囲: chat
        - ログ化しなかった理由: #{reason}
      MD
      store.write("#{term}/log-draft.md", memo)
      metadata["status"] = "closed"
      metadata["awaiting"] = "none"
      metadata["log_status"] = "no_log"
      metadata["save_permission"] = "not_requested"
      metadata["light_memo_status"] = "none"
      metadata["light_memo_source"] = "none"
      append_case_status(metadata, "ログ化しない: #{reason}")
      store.write("#{term}/metadata.toml", SimpleToml.dump(metadata))
      store.write(".codex/state/current-term.toml", term_manager.current_term_toml(false, term_id, term, metadata["classification"], "closed", "none", Time.now.getlocal("+09:00").iso8601))
      { no_log: true, light_memo_saved: false, term_path: term }
    end

    def discard_log_draft(term_id, reason = "学習者が保存しないと指定したため。")
      term = term_manager.find_term(term_id)
      raise "term not found: #{term_id}" unless term

      metadata = SimpleToml.parse(File.read(store.path(term, "metadata.toml")))
      body = <<~MD
        # ログ保存判断

        保存しない。

        # 理由

        #{reason}

        # 扱い

        確定学習ログと軽量メモは保存しない。
      MD
      store.write("#{term}/log-draft.md", body)
      metadata["status"] = "closed"
      metadata["awaiting"] = "none"
      metadata["log_status"] = "discarded"
      metadata["save_permission"] = "declined"
      metadata["light_memo_status"] = "none"
      metadata["light_memo_source"] = "none"
      metadata["updated_at"] = Time.now.getlocal("+09:00").iso8601
      append_case_status(metadata, "ログ候補を保存しない: #{reason}")
      store.write("#{term}/metadata.toml", SimpleToml.dump(metadata))
      store.write(".codex/state/current-term.toml", term_manager.current_term_toml(false, term_id, term, metadata["classification"], "closed", "none", Time.now.getlocal("+09:00").iso8601))
      { discarded: true, light_memo_saved: false, term_path: term }
    end

    def create_light_memo(term_id, reason, source: "agent_judgment")
      term = term_manager.find_term(term_id)
      raise "term not found: #{term_id}" unless term

      metadata = SimpleToml.parse(File.read(store.path(term, "metadata.toml")))
      raise "cannot replace a log draft with a light memo: #{term_id}" if metadata["log_status"] == "draft"

      memo = <<~MD
        # 軽量メモ

        - 記録元: #{source == "agent_judgment" ? "Agent判断" : source}
        - 分類: #{metadata["classification"]}
        - テーマ: #{topic_title(metadata)}
        - 参照した範囲: chat
        - メモを残す理由: #{reason}
      MD
      store.write("#{term}/log-draft.md", memo)
      metadata["log_status"] = "light_memo"
      metadata["light_memo_status"] = "saved"
      metadata["light_memo_source"] = source
      metadata["updated_at"] = Time.now.getlocal("+09:00").iso8601
      append_case_status(metadata, "軽量メモ: #{reason}")
      store.write("#{term}/metadata.toml", SimpleToml.dump(metadata))
      { light_memo_saved: true, source: source, term_path: term }
    end

    def update_daily_profile(date)
      case_path = "learning-cases/#{date}.md"
      return nil unless store.exist?(case_path)

      relative = "notebook/daily-learning-profiles/#{date}.md"
      case_body = store.read(case_path)
      body = <<~MD
        # #{date} 日次学習傾向

        生成元: [#{case_path}](../../#{case_path})

        ## この日の傾向

        #{daily_trend_summary(case_body)}

        ## 苦手傾向の根拠候補

        #{daily_weakness_candidates(case_body)}

        ## learner-profile / Memory 反映候補

        - learner-profile.md: 苦手傾向として複数回出た内容だけ反映候補にする。
        - Memory.md: 質問の繰り返し方、確認順序の癖、学習の進め方を反映候補にする。
      MD
      store.write(relative, body)
      relative
    end

    def rollover_daily_profile_if_needed(today)
      previous = latest_case_date_before(today)
      return { daily_profile_created: false, reason: "前日以前のLearning Caseがありません。" } unless previous

      state_path = ".codex/state/daily-profile-rollover.toml"
      state = store.exist?(state_path) ? SimpleToml.parse(store.read(state_path)) : {}
      return { daily_profile_created: false, reason: "#{previous} は作成済みです。" } if state["last_processed_date"] == previous

      profile_path = update_daily_profile(previous)
      store.write(state_path, SimpleToml.dump("last_processed_date" => previous, "profile_path" => profile_path, "updated_at" => Time.now.getlocal("+09:00").iso8601))
      { daily_profile_created: true, date: previous, profile_path: profile_path }
    end

    def update_learner_profile(log_path, metadata)
      relative = "notebook/learner-profile.md"
      body = store.exist?(relative) ? store.read(relative) : "# learner-profile\n"
      unless body.include?("## Agent認定の苦手傾向")
        body += "\n## Agent認定の苦手傾向\n"
      end
      if metadata["classification"] == "feature" && !body.include?("Route、Controller、Bladeの接続順")
        body += <<~MD

          ### Route、Controller、Bladeの接続順

          - 状態: Agent認定
          - 苦手の種類: 構造理解
          - 技術領域: Laravel / Route / Controller / Blade
          - 確信度: 中
          - 通常表示: 確信度の値は表示しない
          - 根拠ログ:
            - #{metadata["case_path"]}
            - #{log_path}
        MD
      end
      store.write(relative, body)
    end

    def update_memory(metadata)
      relative = "notebook/Memory.md"
      body = store.exist?(relative) ? store.read(relative) : "# Memory\n\nProgrammingAIが学習者との関わりから更新する記憶。\n"
      unless body.include?("## 質問傾向")
        body += "\n## 質問傾向\n"
      end
      if metadata["classification"] == "feature" && !body.include?("複数ファイルのつながりを確認する質問")
        body += <<~MD

          - 複数ファイルのつながりを確認する質問では、入口、処理、出力の順に整理すると学習が進みやすい。
          - 根拠: #{metadata["case_path"]}
        MD
      end
      store.write(relative, body)
    end

    def append_case_status(metadata, note)
      relative = metadata["case_path"] || "learning-cases/#{metadata["date"]}.md"
      return unless store.exist?(relative)

      body = store.read(relative)
      marker = "- term_id: #{metadata["term_id"]}\n- 更新内容: #{note}"
      return if body.include?(marker)

      body += <<~MD

        ### 状態更新

        - term_id: #{metadata["term_id"]}
        - 更新内容: #{note}
        - 更新時刻: #{Time.now.getlocal("+09:00").iso8601}
      MD
      store.write(relative, body)
    end

    def latest_case_date_before(today)
      current = Date.parse(today)
      dates = Dir.glob(store.path("learning-cases", "*.md")).map do |path|
        name = File.basename(path, ".md")
        Date.parse(name) if name.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      rescue Date::Error
        nil
      end.compact
      dates.select { |date| date < current }.max&.strftime("%Y-%m-%d")
    end

    def daily_trend_summary(case_body)
      feature_count = case_body.scan(/- (?:質問分類|分類): feature\b/).size
      unit_count = case_body.scan(/- (?:質問分類|分類): unit\b/).size
      error_count = case_body.scan(/- (?:質問分類|分類): error\b/).size
      assess_count = case_body.scan(/- (?:質問分類|分類): assess\b/).size
      "- feature: #{feature_count}件\n- unit: #{unit_count}件\n- error: #{error_count}件\n- assess: #{assess_count}件"
    end

    def daily_weakness_candidates(case_body)
      candidates = []
      candidates << "- 構造理解: 複数ファイルや処理の流れに関する質問がある。" if case_body.include?("苦手種類: 構造理解") || case_body.match?(/- (?:質問分類|分類): feature\b/)
      candidates << "- 技術知識: コード一文やエラーに関する質問がある。" if case_body.include?("苦手種類: 技術知識") || case_body.match?(/- (?:質問分類|分類): (?:unit|error)\b/)
      candidates << "- 思考プロセス: 評価や判断根拠に関する質問がある。" if case_body.include?("苦手種類: 思考プロセス") || case_body.match?(/- (?:質問分類|分類): assess\b/)
      candidates.empty? ? "- 候補なし" : candidates.join("\n")
    end

    def learning_log(topic, classification, question)
      <<~MD
        # 学習テーマ

        #{topic}

        # 質問分類

        #{classification}

        # 質問した内容

        #{question}

        # つまずきの中核

        学習者が明言した内容:

        - #{question}

        Agentの見立て:

        - 入口、処理、出力を分けて確認する必要がある。

        # 学習前の理解

        不明

        # 学んだ内容

        考え方、処理の流れ、確認順序を分けて整理した。

        # 処理またはコードの流れ

        必要に応じて、入口、処理、出力の順に確認する。

        # 確認したこと

        - 回答と理解確認を行った。

        # 次に同じ問題が出たら見る順番

        1. 入口
        2. 処理
        3. 出力
        4. 検証方法

        # 他でも使える考え方

        複雑な処理は、役割と流れに分けて読む。

        # 未解決事項

        実コードの確認が必要な場合は、参照範囲を指定して確認する。

        # 次に学習すること

        実際のコードで同じ流れを確認する。
      MD
    end

    def topic_title(metadata)
      case metadata["topic_slug"]
      when /route-controller-blade/
        "Route、Controller、Bladeのつながり"
      when /validation/
        "Validationの書き方確認"
      when /fetch/
        "FetchからControllerへの流れ"
      else
        metadata["topic_slug"]
      end
    end
  end

  class Mentor
    attr_reader :store

    def initialize(store)
      @store = store
    end

    def daily_brief
      record = MentorMemory.new(store).primary_record
      trend = trend_text(record)
      <<~MD
        # 最近の学習傾向

        #{trend}

        # 復習

        Q. #{review_question(record)}

        <details>
        <summary>A. 内容の確認</summary>

        #{review_answer(record)}

        </details>

        # 最初に意識する確認ポイント

        #{checkpoint(record)}
      MD
    end

    private

    def trend_text(record)
      return "確定学習ログが増えると、最近の学習傾向をより具体的に出せます。" unless record

      "#{record[:technical_area]} で、#{record[:stumble]} というつまずきが繰り返し出ています。今日はこの内容を優先して確認します。"
    end

    def review_question(record)
      return "前回の質問で、最初に確認する対象はどこでしたか。" unless record

      case record[:technical_area]
      when /Data Provider/
        "データプロバイダーの値は、どの順番でテストメソッドの引数へ渡されますか。"
      when /Closure/
        "`use ($value)` と `use (&$value)` は、外側の変数の扱いがどう違いますか。"
      when /Validation|FormRequest/
        "`Validator::make()` で、検証ルールとエラーメッセージはどこから渡していますか。"
      when /Eloquent|Relation/
        "関連データを作るとき、入力値、ログインユーザー、紐づけ先Modelはそれぞれどこから来ますか。"
      when /Route.*Controller.*Blade/
        "ControllerからBladeへ値を渡すとき、まず確認する場所はどこですか。"
      else
        "今回のつまずきを確認するとき、入口、処理、出力のどこから見ますか。"
      end
    end

    def review_answer(record)
      return "まず質問の対象を一文で言い換え、次に入口、処理、出力の順で確認します。" unless record

      case record[:technical_area]
      when /Data Provider/
        "まずProviderメソッドが配列を返します。次にPHPUnitが各データセットを取り出し、内側の値をテストメソッドの引数へ渡します。"
      when /Closure/
        "`use ($value)` は外側の値をコピーして使います。`use (&$value)` は外側の同じ変数を共有するため、クロージャ内の変更が外側にも反映されます。"
      when /Validation|FormRequest/
        "検証対象データは第1引数、`rules()` の戻り値は第2引数、`messages()` の戻り値は第3引数として渡します。"
      when /Eloquent|Relation/
        "入力値はRequest、投稿者はログインユーザー、紐づけ先はRoute Model Bindingなどで渡されたModelから確認します。"
      when /Route.*Controller.*Blade/
        "まずControllerで `view()` に何を渡しているかを確認します。次にBlade側で、その変数名がどこで使われているかを見ます。"
      else
        "対象を役割ごとに分け、どの値がどこから来て、どこへ渡るかを確認します。"
      end
    end

    def checkpoint(record)
      return "今日は、分からない箇所を見つけたら、先に入口、処理、出力へ分けてから質問する。" unless record

      case record[:weakness_type]
      when "技術知識"
        "まず用語やメソッドの役割を一文で言い換えてから、引数、戻り値、変更される値を確認する。"
      when "構造理解"
        "複数の処理を一気に読まず、入力元、処理担当、保存先または表示先に分けて確認する。"
      when "思考プロセス"
        "合っているかだけでなく、目的、根拠、不足条件、検証方法に分けて判断する。"
      else
        "入口、処理、出力の順番で確認する。"
      end
    end
  end

  class Retention
    attr_reader :store, :today, :days

    def initialize(store, today: Date.today, days: 60)
      @store = store
      @today = today
      @days = days
    end

    def cleanup_test_marked_daily_profiles
      dir = store.path("notebook/daily-learning-profiles")
      return [] unless Dir.exist?(dir)

      cutoff = today - days
      deleted = []
      Dir.children(dir).each do |file|
        next unless file.match?(/\A\d{4}-\d{2}-\d{2}\.md\z/)

        path = File.join(dir, file)
        date = Date.parse(file.sub(".md", ""))
        next unless date < cutoff
        next unless File.read(path).include?("retention-test-generated: true")

        File.delete(path)
        deleted << path.sub("#{store.root}/", "")
      end
      deleted
    end
  end

  class CLI
    attr_reader :store, :classifier, :scope_reader, :term_manager, :log_workflow

    def initialize(root)
      @store = FileStore.new(root)
      @classifier = Classifier.new
      @scope_reader = ScopeReader.new
      @term_manager = TermManager.new(store)
      @log_workflow = LogWorkflow.new(store, term_manager)
    end

    def run(argv)
      command = argv.shift
      case command
      when "init"
        ConfigGuard.new(store).ensure_config
        puts "Initialized ProgrammingAI at #{store.root}"
      when "ask"
        ask(argv.join(" "))
      when "log"
        result = log_workflow.create_log_draft(argv.fetch(0))
        puts JSON.pretty_generate(result)
      when "save-log"
        result = log_workflow.save_log(argv.fetch(0))
        puts JSON.pretty_generate(result)
      when "no-log"
        result = log_workflow.no_log(argv.fetch(0), argv[1..]&.join(" ") || "学習内容がまだ具体化していないため。")
        puts JSON.pretty_generate(result)
      when "discard-log"
        result = log_workflow.discard_log_draft(argv.fetch(0), argv[1..]&.join(" ") || "学習者が保存しないと指定したため。")
        puts JSON.pretty_generate(result)
      when "memo"
        result = log_workflow.create_light_memo(argv.fetch(0), argv[1..]&.join(" ") || "Agentが軽量メモを残す価値があると判断したため。")
        puts JSON.pretty_generate(result)
      when "understanding-answer"
        result = term_manager.complete_understanding(argv.fetch(0), argv[1..]&.join(" "))
        puts JSON.pretty_generate(result)
      when "term-boundary"
        result = term_manager.mark_term_boundary(
          argv.fetch(0),
          trigger: "new_learning_question",
          reason: argv[1..]&.join(" ") || "新しい学習質問が来たため。"
        )
        puts JSON.pretty_generate(result)
      when "pause"
        result = term_manager.pause(argv.fetch(0))
        puts JSON.pretty_generate(result)
      when "resume"
        result = term_manager.resume(argv.fetch(0))
        puts JSON.pretty_generate(result)
      when "mentor"
        MentorMemory.new(store).refresh!(source: "mentor_command")
        puts Mentor.new(store).daily_brief
      when "test"
        Tests.run
      when "help", nil
        puts help
      else
        warn "Unknown command: #{command}"
        puts help
        exit 1
      end
    end

    def ask(question)
      config_state = ConfigGuard.new(store).ensure_config
      trace = []
      trace << trace_step("config-guard", config_state[:ok] ? "設定確認OK" : "設定に修正候補あり")
      intent = term_manager.input_intent(question)
      trace << trace_step("learning-term-manager", "入力意図: #{intent}")
      if intent == "mentor_command"
        rollover = log_workflow.rollover_daily_profile_if_needed(term_manager.today)
        trace << trace_step("profile-memory", rollover[:daily_profile_created] ? "前日分の日次学習傾向を作成" : rollover[:reason])
        mentor_memory = MentorMemory.new(store).refresh!(source: "mentor_command")
        trace << trace_step("mentor", "苦手分析: #{mentor_memory[:weakness_entries]}件")
        record_mentor_session(trigger: "mentor_command", learning_question: false)
        print_agent_trace(trace, config_state[:config])
        puts Mentor.new(store).daily_brief
        return
      end
      if %w[log_request save_permission save_decline].include?(intent)
        result = handle_log_intent(intent)
        trace << trace_step("learning-log-workflow", result[:handled] == false ? "処理不可: #{result[:reason]}" : "ログ処理: #{intent}")
        puts JSON.pretty_generate(with_agent_trace(result.merge(input_intent: intent), trace, config_state[:config]))
        return
      end
      if intent == "log_revision"
        trace << trace_step("learning-log-workflow", "ログ候補の修正待ち")
        puts JSON.pretty_generate(
          with_agent_trace(
            {
              handled: true,
              input_intent: intent,
              message: "学習ログ候補を修正できます。修正後、保存してよいかを指定してください。"
            },
            trace,
            config_state[:config]
          )
        )
        return
      end

      classification = classifier.classify(question)
      trace << trace_step("classifier", "#{classification[:classification]} / #{classification[:confidence]}")
      rollover = log_workflow.rollover_daily_profile_if_needed(term_manager.today)
      trace << trace_step("profile-memory", rollover[:daily_profile_created] ? "前日分の日次学習傾向を作成" : rollover[:reason])
      current = term_manager.current_term
      if current && %w[log_decision log_draft_created log_confirming].include?(current["status"])
        trace << trace_step("learning-term-manager", "確認待ちで停止: #{current["awaiting"]}")
        puts JSON.pretty_generate(
          with_agent_trace(
            {
              handled: false,
              input_intent: intent,
              awaiting: current["awaiting"],
              reason: "現在の学習タームのログ判断または修正が終わるまで、新しい質問を開始しない。"
            },
            trace,
            config_state[:config]
          )
        )
        return
      end

      mentor_brief = nil
      if daily_first_question_mentor?(config_state[:config])
        mentor_memory = MentorMemory.new(store).refresh!(source: "daily_first_learning_question")
        trace << trace_step("mentor", "日付変更後の初回学習質問: #{mentor_memory[:weakness_entries]}件")
        mentor_brief = Mentor.new(store).daily_brief
        record_mentor_session(trigger: "daily_first_learning_question", learning_question: true)
      end

      if current && term_manager.new_topic?(question, classification)
        boundary = term_manager.mark_term_boundary(
          current["term_id"],
          trigger: "new_learning_question",
          reason: "現在のタームと異なるテーマの学習質問を受けたため。"
        )
        trace << trace_step("learning-term-manager", "新しい学習テーマ候補を検出")
        trace << trace_step("learning-log-workflow", "ログ化するか確認")
        puts JSON.pretty_generate(
          with_agent_trace(
            boundary.merge(
              mentor_brief: mentor_brief,
              new_question: question,
              next_step: "現在のタームを保存するか、ログ化しないかを確認してから新しい質問へ進む。"
            ).reject { |_, value| value.nil? },
            trace,
            config_state[:config]
          )
        )
        return
      end

      scope = scope_reader.check(question, classification[:classification])
      trace << trace_step("scope-reader", scope[:allowed] ? "参照範囲OK" : "参照範囲の確認待ち")
      term = term_manager.create_term(question, classification, scope)
      trace << trace_step("learning-term-manager", term[:created] ? "学習ターム作成: #{term[:term_id]}" : "学習ターム未作成: #{term[:reason]}")
      if term[:created]
        record_learning_question unless mentor_brief
        if term[:status] == "awaiting_scope"
          trace << trace_step("scope-reader", "回答前確認で停止")
        else
          trace << trace_step("#{classification[:classification]}-answer", "回答型: #{classification[:classification]}")
        end
        payload = term.merge(classification: classification)
        payload[:mentor_brief] = mentor_brief if mentor_brief
        puts JSON.pretty_generate(with_agent_trace(payload, trace, config_state[:config]))
      else
        print_agent_trace(trace, config_state[:config])
        puts "分類: #{classification[:classification]}"
        puts "分類理由: #{classification[:reason]}"
        puts "確認: #{term[:reason]}"
        puts scope[:confirmation_message] if scope[:confirmation_message]
      end
    end

    def trace_step(agent, detail)
      { agent: agent, detail: detail }
    end

    def daily_first_question_mentor?(config)
      mode = config.fetch("mentor_start_advice_mode", CONFIG_DEFAULTS["mentor_start_advice_mode"])
      return false unless %w[daily_first_question auto_on_start].include?(mode)

      state = mentor_session_state
      today = term_manager.today
      state["last_mentor_date"] != today && state["last_learning_question_date"] != today
    end

    def mentor_session_state
      path = ".codex/state/mentor-session.toml"
      store.exist?(path) ? SimpleToml.parse(store.read(path)) : {}
    end

    def record_mentor_session(trigger:, learning_question:)
      state = mentor_session_state
      today = term_manager.today
      state["last_mentor_date"] = today
      state["last_mentor_trigger"] = trigger
      state["last_learning_question_date"] = today if learning_question
      state["updated_at"] = Time.now.getlocal("+09:00").iso8601
      store.write(".codex/state/mentor-session.toml", SimpleToml.dump(state))
    end

    def record_learning_question
      state = mentor_session_state
      state["last_learning_question_date"] = term_manager.today
      state["updated_at"] = Time.now.getlocal("+09:00").iso8601
      store.write(".codex/state/mentor-session.toml", SimpleToml.dump(state))
    end

    def agent_trace_mode(config)
      mode = config.fetch("agent_trace_mode", CONFIG_DEFAULTS["agent_trace_mode"])
      CONFIG_SCHEMA.fetch("agent_trace_mode").fetch(:allowed).include?(mode) ? mode : CONFIG_DEFAULTS["agent_trace_mode"]
    end

    def agent_trace_payload(trace, config)
      case agent_trace_mode(config)
      when "hidden"
        nil
      when "brief"
        trace.map { |step| step[:agent] }.join(" → ")
      when "detailed"
        trace
      end
    end

    def with_agent_trace(payload, trace, config)
      trace_payload = agent_trace_payload(trace, config)
      trace_payload ? payload.merge(agent_trace: trace_payload) : payload
    end

    def print_agent_trace(trace, config)
      case agent_trace_mode(config)
      when "brief"
        puts "Agent経路: #{agent_trace_payload(trace, config)}"
      when "detailed"
        puts "<details>"
        puts "<summary>Agent処理ログ</summary>"
        puts
        trace.each { |step| puts "- #{step[:agent]}: #{step[:detail]}" }
        puts
        puts "</details>"
      end
    end

    def handle_log_intent(intent)
      term_id = term_manager.current_term_id
      return { handled: false, reason: "進行中の学習タームがありません。" } unless term_id

      current = term_manager.current_term
      case intent
      when "log_request"
        trigger = current && current["awaiting"] == "log_decision" ? "term_boundary" : "explicit_summary_request"
        log_workflow.create_log_draft(term_id, trigger: trigger)
      when "save_permission"
        log_workflow.save_log(term_id)
      when "save_decline"
        if current && current["awaiting"] == "log_decision"
          log_workflow.no_log(term_id, "学習者がログ化しないと指定したため。")
        else
          log_workflow.discard_log_draft(term_id, "学習者が保存しないと指定したため。")
        end
      end
    end

    def help
      <<~TEXT
        ProgrammingAI #{VERSION}

        Usage:
          ruby ProgrammingAIAgent.rb init --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb ask "質問本文" --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb log TERM_ID --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb save-log TERM_ID --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb no-log TERM_ID "理由" --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb discard-log TERM_ID "理由" --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb memo TERM_ID "理由" --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb understanding-answer TERM_ID "返答" --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb term-boundary TERM_ID "理由" --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb pause TERM_ID --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb resume TERM_ID --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb mentor --root ./ProgrammingAI-data
          ruby ProgrammingAIAgent.rb test
      TEXT
    end
  end

  class Tests
    def self.run
      new.run
    end

    def run
      test_classifier
      test_scope_reader
      test_save_flow
      test_explicit_summary_request_and_save_decision
      test_explicit_save_refusal_does_not_create_memo
      test_no_log_and_auto_number
      test_term_boundary_and_agent_memo
      test_new_topic_question_requests_boundary_decision
      test_pause_and_resume
      test_retention_and_alias_error
      test_agent_trace_mode
      test_scope_waiting_creates_learning_case
      test_daily_profile_rollover
      test_mentor_memory_from_logs
      test_daily_first_question_triggers_mentor
      test_daily_first_question_triggers_mentor_with_active_term
      test_classification_labels_are_valid
      test_project_storage_guard
      puts "PASS: ProgrammingAI agent tests"
    end

    def assert(condition, message)
      raise "FAILED: #{message}" unless condition
    end

    def capture_stdout
      original_stdout = $stdout
      buffer = StringIO.new
      $stdout = buffer
      yield
      buffer.string
    ensure
      $stdout = original_stdout
    end

    def with_app
      Dir.mktmpdir("programming_ai") do |dir|
        ENV["PROGRAMMING_AI_DATE"] = "2026-08-06"
        ENV["PROGRAMMING_AI_ALLOW_TEST_ROOT"] = "1"
        cli = CLI.new(dir)
        ConfigGuard.new(cli.store).ensure_config
        yield cli
      ensure
        ENV.delete("PROGRAMMING_AI_DATE")
        ENV.delete("PROGRAMMING_AI_ALLOW_TEST_ROOT")
      end
    end

    def test_classifier
      classifier = Classifier.new
      assert(classifier.classify("RouteとControllerとBladeの流れが分かりません")[:classification] == "feature", "feature classification")
      assert(classifier.classify("$user->books()->create($data) の意味")[:classification] == "unit", "unit classification")
      assert(classifier.classify("このテストで十分ですか")[:classification] == "assess", "assess classification")
      assert(classifier.classify("Call to undefined method App\\Models\\User::books()")[:classification] == "error", "error classification")
    end

    def test_scope_reader
      scope = ScopeReader.new
      result = scope.check("ログイン機能でRoute、Controller、Bladeがどうつながっているか分かりません", "feature")
      assert(!result[:allowed], "feature without explicit scope asks for confirmation")
      secret = scope.check(".env の API_KEY を見てください", "unit")
      assert(!secret[:allowed] && secret[:reason].include?("秘密情報"), "secret scope stops")
    end

    def test_save_flow
      with_app do |cli|
        classification = cli.classifier.classify("resources/views/books/index.blade.php のRoute、Controller、Bladeの流れが分かりません")
        scope = cli.scope_reader.check("resources/views/books/index.blade.php のRoute、Controller、Bladeの流れが分かりません", classification[:classification])
        term = cli.term_manager.create_term("resources/views/books/index.blade.php のRoute、Controller、Bladeの流れが分かりません", classification, scope)
        assert(term[:created], "term created")
        draft = cli.log_workflow.create_log_draft(term[:term_id], trigger: "term_boundary")
        assert(draft[:awaiting] == "save_permission", "save permission is requested after draft")
        saved = cli.log_workflow.save_log(term[:term_id])
        assert(File.exist?(cli.store.path(saved[:log_path])), "confirmed log exists")
        assert(saved[:log_path] == "learning-logs/2026-08-06-001-route-controller-blade-flow.md", "confirmed log is stored directly under learning-logs")
        assert(!saved.key?(:notion_path), "notion draft path is not returned")
        assert(File.exist?(cli.store.path("learning-cases/2026-08-06.md")), "daily learning case exists")
        assert(!Dir.exist?(cli.store.path("notion-drafts")), "notion drafts are not generated")
        current = SimpleToml.parse(File.read(cli.store.path(".codex/state/current-term.toml")))
        assert(current["active"] == false, "current term inactive after save")
      end
    end

    def test_explicit_summary_request_and_save_decision
      with_app do |cli|
        question = "resources/views/books/index.blade.php のRoute、Controller、Bladeの流れが分かりません"
        classification = cli.classifier.classify(question)
        scope = cli.scope_reader.check(question, classification[:classification])
        term = cli.term_manager.create_term(question, classification, scope)
        assert(term[:created], "term created for explicit summary request")

        cli.ask("内容をまとめてほしい")
        metadata = SimpleToml.parse(File.read(cli.store.path(term[:term_path], "metadata.toml")))
        assert(metadata["status"] == "log_draft_created", "summary request enters log confirmation")
        assert(metadata["awaiting"] == "save_permission", "summary request waits for save permission")
        assert(metadata["log_trigger"] == "explicit_summary_request", "summary request trigger is recorded")
        assert(!File.exist?(cli.store.path("learning-logs/2026-08-06-001-route-controller-blade-flow.md")), "summary request does not save immediately")

        cli.ask("保存して")
        metadata = SimpleToml.parse(File.read(cli.store.path(term[:term_path], "metadata.toml")))
        assert(metadata["log_status"] == "saved", "explicit save permission saves the log")
        assert(metadata["save_permission"] == "granted", "save permission is recorded")
        assert(metadata["log_path"] == "learning-logs/2026-08-06-001-route-controller-blade-flow.md", "metadata records direct log path")
      end
    end

    def test_explicit_save_refusal_does_not_create_memo
      with_app do |cli|
        question = "resources/views/books/index.blade.php のRoute、Controller、Bladeの流れが分かりません"
        classification = cli.classifier.classify(question)
        scope = cli.scope_reader.check(question, classification[:classification])
        term = cli.term_manager.create_term(question, classification, scope)
        cli.ask("内容をまとめてほしい")
        cli.ask("保存しない")

        metadata = SimpleToml.parse(File.read(cli.store.path(term[:term_path], "metadata.toml")))
        profile_path = cli.store.path("notebook/daily-learning-profiles/2026-08-06.md")
        assert(metadata["log_status"] == "discarded", "declined draft is discarded")
        assert(metadata["light_memo_status"] == "none", "declined draft does not create a light memo")
        assert(!File.exist?(cli.store.path("learning-logs/2026-08-06-001-route-controller-blade-flow.md")), "declined draft creates no confirmed log")
        assert(!File.exist?(profile_path), "declined draft creates no daily memo")
      end
    end

    def test_no_log_and_auto_number
      with_app do |cli|
        first = cli.term_manager.create_term("resources/views/books/index.blade.php のRoute、Controller、Bladeの流れ", cli.classifier.classify("Route、Controller、Bladeの流れ"), cli.scope_reader.check("resources/views/books/index.blade.php", "feature"))
        second = cli.term_manager.create_term("このバリデーションの書き方で問題ありませんか", cli.classifier.classify("このバリデーションの書き方で問題ありませんか"), cli.scope_reader.check("このバリデーションの書き方で問題ありませんか", "assess"))
        assert(first[:term_id].include?("-001-"), "first term sequence")
        assert(second[:term_id].include?("-002-"), "second term sequence")
        cli.log_workflow.no_log(second[:term_id], "評価対象コードが未提示で、学習内容がまだ具体化していないため。")
        assert(!File.exist?(cli.store.path("learning-logs/2026-08-06-002-validation-rule-check.md")), "no confirmed log for no-log")
        assert(File.read(cli.store.path("learning-cases/2026-08-06.md")).include?("ログ化しない"), "no-log status is recorded in learning case")
      end
    end

    def test_term_boundary_and_agent_memo
      with_app do |cli|
        question = "resources/views/books/index.blade.php のRoute、Controller、Bladeの流れが分かりません"
        classification = cli.classifier.classify(question)
        scope = cli.scope_reader.check(question, classification[:classification])
        term = cli.term_manager.create_term(question, classification, scope)
        boundary = cli.term_manager.complete_understanding(term[:term_id], "Routeが入口だと理解しました。")
        assert(boundary[:term_boundary_candidate], "understanding answer becomes a boundary candidate")
        assert(boundary[:awaiting] == "log_decision", "boundary candidate waits for log decision")

        cli.ask("ログ化しない")
        metadata = SimpleToml.parse(File.read(cli.store.path(term[:term_path], "metadata.toml")))
        assert(metadata["log_status"] == "no_log", "boundary no-log decision records no_log")
        assert(metadata["light_memo_status"] == "none", "boundary no-log decision does not create a daily light memo")
        current = SimpleToml.parse(File.read(cli.store.path(".codex/state/current-term.toml")))
        assert(current["active"] == false, "no-log boundary closes the term")

        memo_term = cli.term_manager.create_term(question, classification, scope)
        memo = cli.log_workflow.create_light_memo(memo_term[:term_id], "同じ確認順序のつまずきが繰り返されたため。")
        assert(memo[:light_memo_saved], "agent judgment saves a light memo")
        assert(memo[:source] == "agent_judgment", "agent memo source is recorded")
        profile = File.read(cli.store.path("learning-cases/2026-08-06.md"))
        assert(profile.include?("軽量メモ"), "agent memo is visible in learning case")
      end
    end

    def test_new_topic_question_requests_boundary_decision
      with_app do |cli|
        question = "resources/views/books/index.blade.php のRoute、Controller、Bladeの流れが分かりません"
        classification = cli.classifier.classify(question)
        scope = cli.scope_reader.check(question, classification[:classification])
        term = cli.term_manager.create_term(question, classification, scope)

        cli.ask("fetchでControllerへ送る流れが分かりません\nfetch('/books')")
        metadata = SimpleToml.parse(File.read(cli.store.path(term[:term_path], "metadata.toml")))
        assert(metadata["status"] == "log_decision", "new topic requests a boundary decision")
        assert(metadata["term_boundary_trigger"] == "new_learning_question", "new topic trigger is recorded")
        assert(metadata["awaiting"] == "log_decision", "new topic waits for log decision")
      end
    end

    def test_pause_and_resume
      with_app do |cli|
        classification = cli.classifier.classify("fetchでControllerへ送る流れが分かりません\nfetch('/books')")
        scope = cli.scope_reader.check("fetchでControllerへ送る流れが分かりません\nfetch('/books')", classification[:classification])
        term = cli.term_manager.create_term("fetchでControllerへ送る流れが分かりません\nfetch('/books')", classification, scope)
        cli.term_manager.pause(term[:term_id])
        paused = SimpleToml.parse(File.read(cli.store.path(".codex/state/current-term.toml")))
        assert(paused["status"] == "paused", "paused status")
        cli.term_manager.resume(term[:term_id])
        resumed = SimpleToml.parse(File.read(cli.store.path(".codex/state/current-term.toml")))
        assert(resumed["status"] == "understanding_check", "resumed status")
        assert(resumed["awaiting"] == "understanding_answer", "resumed awaiting")
      end
    end

    def test_retention_and_alias_error
      with_app do |cli|
        cli.store.write("notebook/daily-learning-profiles/2026-06-06.md", "# old\n\nretention-test-generated: true\n")
        cli.store.write("notebook/daily-learning-profiles/2026-06-07.md", "# boundary\n\nretention-test-generated: true\n")
        deleted = Retention.new(cli.store, today: Date.new(2026, 8, 6), days: 60).cleanup_test_marked_daily_profiles
        assert(deleted.any? { |path| path.include?("2026-06-06.md") }, "old daily profile deleted")
        assert(File.exist?(cli.store.path("notebook/daily-learning-profiles/2026-06-07.md")), "boundary daily profile kept")

        invalid_alias_config = SimpleToml.dump(CONFIG_DEFAULTS.merge("technical_area_aliases" => []))
        invalid_alias_config += "\n[[technical_area_aliases]]\nfrom = \"Validation\"\n"
        cli.store.write(".codex/config.toml", invalid_alias_config)
        result = ConfigGuard.new(cli.store).validate_aliases
        assert(!result[:ok], "alias format error detected")
        assert(result[:stopped_processing] == ["alias_analysis"], "only alias analysis stops")
        assert(result[:continue_processing].include?("normal_answer"), "normal answers continue")
      end
    end

    def test_agent_trace_mode
      with_app do |cli|
        config = SimpleToml.parse(cli.store.read(".codex/config.toml"))
        config["agent_trace_mode"] = "brief"
        cli.store.write(".codex/config.toml", SimpleToml.dump(config))

        output = capture_stdout do
          cli.ask("routes/web.php のRoute、Controller、Bladeの流れが分かりません")
        end
        parsed = JSON.parse(output)
        assert(parsed["agent_trace"].include?("config-guard"), "brief trace includes config guard")
        assert(parsed["agent_trace"].include?("classifier"), "brief trace includes classifier")
        assert(parsed["agent_trace"].include?("feature-answer"), "brief trace includes answer sub agent")

        cli.log_workflow.create_log_draft(parsed.fetch("term_id"), trigger: "term_boundary")
        config["agent_trace_mode"] = "hidden"
        cli.store.write(".codex/config.toml", SimpleToml.dump(config))
        output = capture_stdout do
          cli.ask("保存して")
        end
        parsed = JSON.parse(output)
        assert(!parsed.key?("agent_trace"), "hidden trace omits trace payload")

        config["agent_trace_mode"] = "invalid"
        cli.store.write(".codex/config.toml", SimpleToml.dump(config))
        validation = ConfigGuard.new(cli.store).validate
        assert(!validation[:ok], "invalid trace mode is rejected")
      end
    end

    def test_scope_waiting_creates_learning_case
      with_app do |cli|
        question = "ログイン機能でRoute、Controller、Bladeがどうつながっているか分かりません"
        classification = cli.classifier.classify(question)
        scope = cli.scope_reader.check(question, classification[:classification])
        term = cli.term_manager.create_term(question, classification, scope)
        assert(term[:created], "scope waiting learning question creates a case")
        assert(term[:status] == "awaiting_scope", "scope waiting status")
        body = File.read(cli.store.path("learning-cases/2026-08-06.md"))
        assert(body.include?("状態: awaiting_scope"), "scope waiting is recorded in daily case")
      end
    end

    def test_daily_profile_rollover
      with_app do |cli|
        question = "resources/views/books/index.blade.php のRoute、Controller、Bladeの流れが分かりません"
        classification = cli.classifier.classify(question)
        scope = cli.scope_reader.check(question, classification[:classification])
        cli.term_manager.create_term(question, classification, scope)
        ENV["PROGRAMMING_AI_DATE"] = "2026-08-07"

        result = cli.log_workflow.rollover_daily_profile_if_needed(cli.term_manager.today)
        assert(result[:daily_profile_created], "daily profile created after date changes")
        assert(File.exist?(cli.store.path("notebook/daily-learning-profiles/2026-08-06.md")), "previous day profile exists")
      end
    end

    def test_mentor_memory_from_logs
      with_app do |cli|
        cli.store.write("learning-logs/2026-08-05-001-php-closure.md", <<~MD)
          # 学習テーマ

          PHPクロージャの参照キャプチャ

          # 質問分類

          unit

          # つまずきの中核

          `use (&$ratingIndex)` の `&` が何をしているのか分からなかった。
        MD
        cli.store.write("learning-logs/2026-08-06-001-php-closure.md", <<~MD)
          # 学習テーマ

          クロージャ内で外側の変数を変更する

          # 質問分類

          unit

          # つまずきの中核

          `use ($value)` と `use (&$value)` の違いが曖昧だった。
        MD

        result = MentorMemory.new(cli.store).refresh!(source: "test")
        memory = cli.store.read(".codex/agents/mentor/MEMORY.md")
        brief = Mentor.new(cli.store).daily_brief

        assert(result[:weakness_entries] >= 1, "mentor memory has weakness entries")
        assert(memory.include?("PHP / Closure"), "mentor memory records technical area")
        assert(memory.include?("苦手種類: 技術知識"), "mentor memory records weakness type")
        assert(memory.include?("確信度: 中"), "two similar items become medium confidence")
        assert(brief.include?("use ($value)"), "mentor brief uses mentor memory")
        assert(!brief.include?("確信度"), "mentor brief hides confidence value")
      end
    end

    def test_daily_first_question_triggers_mentor
      with_app do |cli|
        cli.store.write("learning-logs/2026-08-05-001-php-closure.md", <<~MD)
          # 学習テーマ

          PHPクロージャの参照キャプチャ

          # 質問分類

          unit

          # つまずきの中核

          `use (&$ratingIndex)` の `&` が何をしているのか分からなかった。
        MD
        cli.store.write("learning-logs/2026-08-05-002-php-closure.md", <<~MD)
          # 学習テーマ

          クロージャのuse

          # 質問分類

          unit

          # つまずきの中核

          `use ($value)` と `use (&$value)` の違いが曖昧だった。
        MD

        output = capture_stdout do
          cli.ask("$request->rules() の意味を教えてください")
        end
        parsed = JSON.parse(output)
        state = SimpleToml.parse(cli.store.read(".codex/state/mentor-session.toml"))

        assert(parsed["mentor_brief"].include?("# 最近の学習傾向"), "first daily learning question includes mentor brief")
        assert(parsed["agent_trace"].include?("mentor"), "trace shows mentor route")
        assert(state["last_learning_question_date"] == "2026-08-06", "daily first learning question date is recorded")
        assert(File.exist?(cli.store.path(".codex/agents/mentor/MEMORY.md")), "mentor memory is refreshed")
      end
    end

    def test_daily_first_question_triggers_mentor_with_active_term
      with_app do |cli|
        cli.store.write("learning-logs/2026-08-05-001-php-closure.md", <<~MD)
          # 学習テーマ

          PHPクロージャの参照キャプチャ

          # 質問分類

          unit

          # つまずきの中核

          `use (&$ratingIndex)` の `&` が何をしているのか分からなかった。
        MD
        cli.store.write("learning-logs/2026-08-05-002-php-closure.md", <<~MD)
          # 学習テーマ

          クロージャのuse

          # 質問分類

          unit

          # つまずきの中核

          `use ($value)` と `use (&$value)` の違いが曖昧だった。
        MD

        ENV["PROGRAMMING_AI_DATE"] = "2026-08-05"
        capture_stdout do
          cli.ask("$request->rules() の意味を教えてください")
        end

        ENV["PROGRAMMING_AI_DATE"] = "2026-08-06"
        output = capture_stdout do
          cli.ask("fetchでControllerへ送る流れが分かりません")
        end
        parsed = JSON.parse(output)
        state = SimpleToml.parse(cli.store.read(".codex/state/mentor-session.toml"))

        assert(parsed["term_boundary_candidate"] == true, "active old term still asks boundary")
        assert(parsed["mentor_brief"].include?("# 復習"), "active old term still includes mentor review")
        assert(parsed["agent_trace"].include?("mentor"), "trace shows mentor route with active term")
        assert(state["last_learning_question_date"] == "2026-08-06", "active-term daily mentor records learning question date")
      end
    end

    def test_classification_labels_are_valid
      with_app do |cli|
        cli.store.write("learning-cases/2026-08-05.md", <<~MD)
          # Learning Cases: 2026-08-05

          ## まとめ依頼の記録

          - 分類: summary
          - 質問: 処理全体をまとめたい。
          - つまずき: 個別処理だけでなく、処理全体の役割分担を整理したい。
        MD
        cli.store.write("learning-logs/2026-08-05-001-test-label.md", <<~MD)
          # 学習テーマ

          PHPUnitのデータプロバイダー

          # 質問分類

          test

          # つまずきの中核

          テストメソッドの引数がどこから来るのか分からなかった。
        MD

        MentorMemory.new(cli.store).refresh!(source: "test")
        memory = cli.store.read(".codex/agents/mentor/MEMORY.md")
        assert(!memory.include?("分類: summary"), "summary is not kept as a classification")
        assert(!memory.include?("分類: test"), "test is not kept as a classification")
        assert(memory.match?(/分類: (feature|unit|assess|error)/), "mentor memory uses valid classifications")
      end

      invalid = invalid_classification_entries(PROJECT_ROOT)
      assert(invalid.empty?, "project learning records must not contain invalid classifications: #{invalid.join(", ")}")
    end

    def test_project_storage_guard
      Dir.mktmpdir("programming_ai_guard") do |dir|
        store = FileStore.new(dir)
        begin
          store.write("learning-cases/2026-08-06.md", "# should stop\n")
          assert(false, "project data write outside project root should stop")
        rescue RuntimeError => error
          assert(error.message.include?("Project folder"), "project storage guard error")
        end
      end
    end

    def invalid_classification_entries(root)
      files = Dir.glob(File.join(root, "{learning-cases,learning-logs,.codex/agents/mentor}", "**", "*.md"), File::FNM_EXTGLOB)
      invalid = []
      files.each do |file|
        lines = File.readlines(file)
        lines.each_with_index do |line, index|
          inline = line.match(/^\s*-\s*(?:質問分類|分類):\s*(.+)$/)
          if inline && invalid_classification_value?(inline[1])
            invalid << "#{file.sub("#{root}/", "")}:#{index + 1}:#{inline[1]}"
          end

          next unless line.strip == "# 質問分類"

          value = lines[(index + 1)..].to_a.map(&:strip).find { |candidate| !candidate.empty? && !candidate.start_with?("#") }
          if value && invalid_classification_value?(value)
            invalid << "#{file.sub("#{root}/", "")}:#{index + 3}:#{value}"
          end
        end
      end
      invalid
    end

    def invalid_classification_value?(value)
      labels = value.to_s.split(/[,\s、]+/).map(&:strip).reject(&:empty?)
      labels.empty? || labels.any? { |label| !VALID_CLASSIFICATIONS.include?(label) }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  argv = ARGV.dup
  root_index = argv.index("--root")
  root = if root_index
           value = argv[root_index + 1]
           argv.slice!(root_index, 2)
           value
         else
           ProgrammingAI::PROJECT_ROOT
         end
  ProgrammingAI::CLI.new(root).run(argv)
end
