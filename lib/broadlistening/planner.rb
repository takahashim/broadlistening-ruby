# frozen_string_literal: true

require "pathname"
require "digest"

module Broadlistening
  class Planner
    attr_reader :spec_loader, :config, :status, :output_dir

    def initialize(config:, status:, output_dir:, spec_loader: nil)
      @config = config
      @status = status
      @output_dir = Pathname.new(output_dir)
      @spec_loader = spec_loader || SpecLoader.default
      @previous_jobs = status.previous_completed_jobs
    end

    def create_plan(force: false, only: nil)
      plan = []

      spec_loader.specs.each do |spec|
        step_name = spec[:step]
        run, reason = decide_step(spec, plan, force: force, only: only)
        plan << { step: step_name, run: run, reason: reason }
      end

      plan
    end

    def extract_current_params(step_name)
      case step_name.to_sym
      when :extraction
        { model: config.model, prompt: config.prompts[:extraction] }
      when :embedding
        { model: config.embedding_model }
      when :clustering
        { cluster_nums: config.cluster_nums }
      when :initial_labelling
        { model: config.model, prompt: config.prompts[:initial_labelling] }
      when :merge_labelling
        { model: config.model, prompt: config.prompts[:merge_labelling] }
      when :overview
        { model: config.model, prompt: config.prompts[:overview] }
      when :aggregation
        {}
      else
        {}
      end
    end

    private

    def decide_step(spec, plan, force:, only:)
      step_name = spec[:step]

      # 強制実行
      return [ true, "forced with -f" ] if force

      # 特定ステップのみ実行
      if only
        return [ true, "forced this step with -o" ] if only.to_sym == step_name

        return [ false, "forced another step with -o" ]

      end

      # 前回実行記録の確認
      prev_job = find_previous_job(step_name)
      return [ true, "no trace of previous run" ] unless prev_job

      # 出力ファイルの存在確認
      output_file = output_dir / spec[:output_file]
      return [ true, "previous output not found" ] unless output_file.exist?

      # 依存ステップの確認
      deps = spec[:dependencies][:steps]
      changing_deps = plan.select { |p| deps.include?(p[:step]) && p[:run] }
      if changing_deps.any?
        dep_names = changing_deps.map { |d| d[:step] }.join(", ")
        return [ true, "dependent steps will re-run: #{dep_names}" ]
      end

      # パラメータ変更の確認
      changed_params = detect_param_changes(spec, prev_job)
      return [ true, "parameters changed: #{changed_params.join(', ')}" ] if changed_params.any?

      # 変更なし - スキップ
      [ false, "nothing changed" ]
    end

    def find_previous_job(step_name)
      @previous_jobs.find { |j| j[:step] == step_name.to_s }
    end

    def detect_param_changes(spec, prev_job)
      params_to_check = spec[:dependencies][:params]
      prev_params = prev_job[:params] || {}
      current_params = extract_current_params(spec[:step])

      params_to_check.select do |param|
        current_value = current_params[param]
        # prev_paramsのキーは文字列の場合もある
        prev_value = prev_params[param.to_s] || prev_params[param]

        # プロンプトなど長い文字列はハッシュ化して比較
        if current_value.is_a?(String) && current_value.length > 100
          Digest::SHA256.hexdigest(current_value) != prev_value
        else
          current_value != prev_value
        end
      end
    end
  end
end
