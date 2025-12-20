# frozen_string_literal: true

require "pathname"
require "digest"

module Broadlistening
  class Planner
    attr_reader :spec_loader, :config, :status, :output_dir, :input_file

    def initialize(config:, status:, output_dir:, spec_loader: nil, input_file: nil)
      @config = config
      @status = status
      @output_dir = Pathname.new(output_dir)
      @spec_loader = spec_loader || SpecLoader.default
      @all_completed_jobs = status.all_completed_jobs
      @input_file = input_file
    end

    def create_plan(force: false, only: nil, from_step: nil)
      plan = []
      steps = spec_loader.steps
      from_index = from_step ? steps.index(from_step.to_sym) : nil

      spec_loader.specs.each_with_index do |spec, idx|
        step_name = spec[:step]

        if from_step && from_index && idx < from_index
          plan << PlanStep.new(step: step_name, run: false, reason: "before --from step")
        else
          run, reason = decide_step(spec, plan, force: force, only: only)
          if from_step && from_index && idx == from_index
            run = true
            reason = "resuming from --from #{from_step}"
          end
          plan << PlanStep.new(step: step_name, run: run, reason: reason)
        end
      end

      plan
    end

    def extract_current_params(step_name)
      case step_name.to_sym
      when :extraction
        { model: config.model, prompt: config.prompts[:extraction], limit: config.limit, input: input_file }
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

    def extract_file_info(step_name)
      spec = spec_loader.find(step_name)
      input_files = []
      output_files = []

      if spec && spec[:dependencies][:steps].any?
        spec[:dependencies][:steps].each do |dep_step|
          dep_output = Context::OUTPUT_FILES[dep_step]
          case dep_output
          when Hash
            dep_output.each_value { |f| input_files << (output_dir / f).to_s }
          when String
            input_files << (output_dir / dep_output).to_s
          end
        end
      end

      step_output = Context::OUTPUT_FILES[step_name]
      case step_output
      when Hash
        step_output.each_value { |f| output_files << (output_dir / f).to_s }
      when String
        output_files << (output_dir / step_output).to_s
      end

      { input: input_files, output: output_files }
    end

    private

    def decide_step(spec, plan, force:, only:)
      step_name = spec[:step]

      return [ true, "forced with -f" ] if force

      if only
        return [ true, "forced this step with -o" ] if only.to_sym == step_name

        return [ false, "forced another step with -o" ]
      end

      prev_job = find_previous_job(step_name)
      return [ true, "no trace of previous run" ] unless prev_job

      unless output_files_exist?(spec[:step])
        return [ true, "previous output not found" ]
      end

      deps = spec[:dependencies][:steps]
      changing_deps = plan.select { |p| deps.include?(p.step) && p.run? }
      if changing_deps.any?
        dep_names = changing_deps.map(&:step).join(", ")
        return [ true, "dependent steps will re-run: #{dep_names}" ]
      end

      changed_params = detect_param_changes(spec, prev_job)
      return [ true, "parameters changed: #{changed_params.join(', ')}" ] if changed_params.any?

      [ false, "nothing changed" ]
    end

    def find_previous_job(step_name)
      @all_completed_jobs.find { |j| j.step == step_name.to_s }
    end

    def output_files_exist?(step_name)
      file_config = Context::OUTPUT_FILES[step_name]
      return false unless file_config

      case file_config
      when Hash
        # Multiple files (e.g., extraction: { args: "args.csv", relations: "relations.csv" })
        file_config.values.all? { |filename| (output_dir / filename).exist? }
      when String
        # Single file
        (output_dir / file_config).exist?
      else
        false
      end
    end

    def detect_param_changes(spec, prev_job)
      params_to_check = spec[:dependencies][:params].dup
      # Ruby CLI specific: also track input file for extraction step
      params_to_check << :input if spec[:step] == :extraction
      prev_params = prev_job.params
      current_params = extract_current_params(spec[:step])

      params_to_check.select do |param|
        current_value = current_params[param]
        prev_value = prev_params[param]

        if current_value.is_a?(String) && current_value.length > LONG_STRING_THRESHOLD
          Digest::SHA256.hexdigest(current_value) != prev_value
        else
          current_value != prev_value
        end
      end
    end
  end
end
