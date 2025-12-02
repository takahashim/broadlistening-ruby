# frozen_string_literal: true

module Broadlistening
  module Steps
    class Overview < BaseStep
      def execute
        return context if context.labels.empty?

        top_labels = find_top_level_labels(context.labels)
        overview = generate_overview(top_labels)

        context.overview = overview
        context
      end

      private

      def find_top_level_labels(labels)
        min_level = labels.values.map { |l| l[:level] }.min
        labels.values.select { |l| l[:level] == min_level }
      end

      def generate_overview(top_labels)
        input = top_labels.map { |l| "- #{l[:label]}: #{l[:description]}" }.join("\n")

        result = llm_client.chat(
          system: config.prompts[:overview],
          user: input
        )
        context.add_token_usage(result.token_usage)
        result.content
      rescue StandardError => e
        warn "Failed to generate overview: #{e.message}"
        ""
      end
    end
  end
end
