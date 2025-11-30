# frozen_string_literal: true

module Broadlistening
  module Steps
    class Embedding < BaseStep
      BATCH_SIZE = 1000

      def execute
        return context if context.arguments.empty?

        embeddings = compute_embeddings(context.arguments)
        attach_embeddings_to_arguments(context.arguments, embeddings)

        context
      end

      private

      def compute_embeddings(arguments)
        texts = arguments.map(&:argument)
        embeddings = []
        total_batches = (texts.size.to_f / BATCH_SIZE).ceil

        texts.each_slice(BATCH_SIZE).with_index(1) do |batch, batch_num|
          batch_embeddings = llm_client.embed(batch)
          embeddings.concat(batch_embeddings)
          notify_progress(current: batch_num, total: total_batches)
        end

        embeddings
      end

      def attach_embeddings_to_arguments(arguments, embeddings)
        arguments.each_with_index do |arg, idx|
          arg.embedding = embeddings[idx]
        end
      end
    end
  end
end
