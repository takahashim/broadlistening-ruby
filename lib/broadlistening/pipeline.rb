# frozen_string_literal: true

require "pathname"

module Broadlistening
  # Orchestrates the execution of the broadlistening pipeline.
  #
  # The Pipeline is responsible for:
  # - Coordinating step execution order
  # - Managing execution status and locking
  # - Handling incremental execution (skip unchanged steps)
  # - Emitting instrumentation events
  #
  # @example Basic usage
  #   pipeline = Pipeline.new(api_key: "...", cluster_nums: [5, 15])
  #   result = pipeline.run(comments, output_dir: "/path/to/output")
  #
  # @example Force re-run all steps
  #   pipeline.run(comments, output_dir: "/path/to/output", force: true)
  #
  # @example Run only a specific step
  #   pipeline.run(comments, output_dir: "/path/to/output", only: :clustering)
  class Pipeline
    attr_reader :config, :spec_loader

    def initialize(config, spec_loader: nil)
      @config = config.is_a?(Config) ? config : Config.new(config)
      @spec_loader = spec_loader || SpecLoader.default
    end

    # Run the pipeline with incremental execution support
    #
    # @param comments [Array] Array of comments to process
    # @param output_dir [String] Directory for output files and status tracking
    # @param force [Boolean] Force re-run all steps
    # @param only [Symbol, nil] Run only the specified step
    # @param from_step [Symbol, nil] Resume from the specified step
    # @param input_dir [String, nil] Directory containing input files for resuming
    # @return [Hash] The result of the pipeline
    def run(comments, output_dir:, force: false, only: nil, from_step: nil, input_dir: nil)
      output_path = Pathname.new(output_dir)
      status = Status.new(output_path)

      if status.locked?
        status_file = output_path / "status.json"
        raise Error, "Pipeline is locked. Another process may be running.\nTo unlock, delete: #{status_file}"
      end

      # input_dirが指定されている場合、そこからコンテキストを読み込む
      if input_dir
        input_path = Pathname.new(input_dir)
        context = Context.load_from_dir(input_path)
        context.output_dir = output_path
        # 必要なファイルをoutput_dirにコピー
        copy_required_files(input_path, output_path, from_step)
      else
        context = Context.load_from_dir(output_path)
        context.output_dir = output_path
      end

      # Normalize comments if not already loaded
      context.comments = normalize_comments(comments) if context.comments.empty?

      # Apply auto cluster_nums calculation if enabled
      @config = @config.with_calculated_cluster_nums(context.comments.size)

      planner = Planner.new(
        config: @config,
        status: status,
        output_dir: output_path,
        spec_loader: @spec_loader
      )
      plan = planner.create_plan(force: force, only: only, from_step: from_step)

      status.start_pipeline(plan)

      execute_pipeline(plan, status, planner, context, output_path)

      status.complete_pipeline
      context.result
    rescue StandardError => e
      status&.error_pipeline(e)
      raise
    end

    private

    def execute_pipeline(plan, status, planner, context, output_path)
      instrument("pipeline.broadlistening", comment_count: context.comments.size) do
        plan.each_with_index do |step_plan, index|
          if step_plan.run?
            execute_step(step_plan.step, index, status, planner, context, output_path)
          else
            notify_skip(step_plan.step, step_plan.reason)
          end
        end
      end
    end

    def execute_step(step_name, index, status, planner, context, output_path)
      status.start_step(step_name)
      start_time = Time.now
      token_usage_before = context.token_usage.dup

      steps = @spec_loader.steps
      params = planner.extract_current_params(step_name)
      file_info = planner.extract_file_info(step_name)
      payload = { step: step_name, step_index: index, step_total: steps.size, params: params, files: file_info }

      # Notify step start before execution
      instrument("step.start.broadlistening", payload)

      step = step_class(step_name).new(@config, context)
      step.execute

      # Notify step completion after execution
      instrument("step.broadlistening", payload)

      duration = Time.now - start_time
      step_token_usage = TokenUsage.new(
        input: context.token_usage.input - token_usage_before.input,
        output: context.token_usage.output - token_usage_before.output
      )
      status.complete_step(step_name, params: params, duration: duration, token_usage: step_token_usage)

      context.save_step(step_name, output_path)
    end

    def normalize_comments(comments)
      comments.map do |comment|
        if comment.is_a?(Comment)
          comment
        elsif comment.is_a?(Hash)
          Comment.from_hash(comment, property_names: @config.property_names)
        else
          Comment.from_object(comment, property_names: @config.property_names)
        end
      end
    end

    def notify_skip(step_name, reason)
      ActiveSupport::Notifications.instrument("step.skip.broadlistening", {
                                                step: step_name,
                                                reason: reason
                                              })
    end

    def instrument(event_name, payload = {}, &block)
      ActiveSupport::Notifications.instrument(event_name, payload, &block)
    end

    def step_class(name)
      Broadlistening::Steps.const_get(name.to_s.camelize)
    end

    def copy_required_files(input_path, output_path, from_step)
      steps = @spec_loader.steps
      from_index = steps.index(from_step.to_sym)
      return unless from_index

      # from_stepより前のステップの出力ファイルをコピー
      steps[0...from_index].each do |step|
        file_config = Context::OUTPUT_FILES[step]
        files = case file_config
        when Hash then file_config.values
        when String then [ file_config ]
        else []
        end

        files.each do |filename|
          src = input_path / filename
          dst = output_path / filename
          FileUtils.cp(src, dst) if src.exist? && !dst.exist?
        end
      end
    end
  end
end
