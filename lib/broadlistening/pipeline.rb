# frozen_string_literal: true

module Broadlistening
  class Pipeline
    STEPS = %i[
      extraction
      embedding
      clustering
      initial_labelling
      merge_labelling
      overview
      aggregation
    ].freeze

    attr_reader :config, :context

    def initialize(options = {})
      @config = options.is_a?(Config) ? options : Config.new(options)
      @context = {}
    end

    # Run the pipeline
    #
    # @param comments [Array] Array of comments to process
    # @param resume_from [Symbol, nil] Step to resume from (skips previous steps)
    # @param context [Hash, nil] Previous context to restore when resuming
    # @return [Hash] The result of the pipeline
    def run(comments, resume_from: nil, context: nil)
      if resume_from && context
        validate_resume_from!(resume_from)
        @context = context
      else
        normalized_comments = normalize_comments(comments)
        @context = { comments: normalized_comments }
      end

      steps_to_run = determine_steps_to_run(resume_from)

      instrument("pipeline.broadlistening", comment_count: @context[:comments]&.size || 0) do
        steps_to_run.each do |step_name, index|
          run_step(step_name, index)
        end
      end

      self.context[:result]
    end

    private

    def validate_resume_from!(resume_from)
      return if STEPS.include?(resume_from)

      raise ArgumentError, "Invalid step: #{resume_from}. Valid steps: #{STEPS.join(', ')}"
    end

    def determine_steps_to_run(resume_from)
      return STEPS.each_with_index.to_a unless resume_from

      start_index = STEPS.index(resume_from)
      STEPS[start_index..].each_with_index.map { |step, i| [step, start_index + i] }
    end

    def run_step(step_name, index)
      payload = {
        step: step_name,
        step_index: index,
        step_total: STEPS.size
      }

      instrument("step.broadlistening", payload) do
        step = step_class(step_name).new(config, @context)
        @context = step.execute
      end
    end

    def instrument(event_name, payload = {}, &block)
      ActiveSupport::Notifications.instrument(event_name, payload, &block)
    end

    def normalize_comments(comments)
      comments.map do |comment|
        if comment.is_a?(Hash)
          {
            id: comment[:id] || comment["id"],
            body: comment[:body] || comment["body"],
            proposal_id: comment[:proposal_id] || comment["proposal_id"]
          }
        else
          {
            id: comment.id,
            body: comment.body,
            proposal_id: comment.respond_to?(:proposal_id) ? comment.proposal_id : nil
          }
        end
      end
    end

    def step_class(name)
      Broadlistening::Steps.const_get(name.to_s.camelize)
    end
  end
end
