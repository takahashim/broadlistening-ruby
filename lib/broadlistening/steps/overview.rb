# frozen_string_literal: true

module Broadlistening
  module Steps
    class Overview < BaseStep
      def execute
        labels = context[:labels]
        return context.merge(overview: "") if labels.empty?

        top_labels = find_top_level_labels(labels)
        overview = generate_overview(top_labels)

        context.merge(overview: overview)
      end

      private

      def find_top_level_labels(labels)
        min_level = labels.values.map { |l| l[:level] }.min
        labels.values.select { |l| l[:level] == min_level }
      end

      def generate_overview(top_labels)
        input = top_labels.map { |l| "- #{l[:label]}: #{l[:description]}" }.join("\n")

        llm_client.chat(
          system: config.prompts[:overview],
          user: input
        )
      rescue StandardError => e
        warn "Failed to generate overview: #{e.message}"
        ""
      end
    end
  end
end
