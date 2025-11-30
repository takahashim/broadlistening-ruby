# frozen_string_literal: true

module Broadlistening
  module Steps
    class BaseStep
      attr_reader :config, :context

      def initialize(config, context)
        @config = config
        @context = context
      end

      def execute
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      protected

      def llm_client
        @llm_client ||= Services::LlmClient.new(config)
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
