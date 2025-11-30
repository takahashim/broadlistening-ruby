# frozen_string_literal: true

module Broadlistening
  module Steps
    class BaseStep
      attr_reader :config, :context

      # @param config [Config] Pipeline configuration
      # @param context [Context] Pipeline context
      def initialize(config, context)
        @config = config
        @context = context

        raise ArgumentError, "context must be a Context, got #{context.class}" unless context.is_a?(Context)
      end

      def execute
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      protected

      def llm_client
        @llm_client ||= LlmClient.new(config)
      end

      def instrument(event_name, payload = {}, &block)
        ActiveSupport::Notifications.instrument(event_name, payload, &block)
      end

      def notify_progress(current:, total:, message: nil)
        instrument("progress.broadlistening", {
          step: self.class.name.demodulize.underscore,
          current: current,
          total: total,
          percentage: total.positive? ? (current.to_f / total * 100).round(1) : 0,
          message: message
        })
      end
    end
  end
end
