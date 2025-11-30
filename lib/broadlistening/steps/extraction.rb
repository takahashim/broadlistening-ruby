# frozen_string_literal: true

module Broadlistening
  module Steps
    class Extraction < BaseStep
      def execute
        comments = context[:comments]
        return context.merge(arguments: [], relations: []) if comments.empty?

        results = extract_opinions_in_parallel(comments)
        arguments, relations = build_arguments_and_relations(comments, results)

        context.merge(
          arguments: arguments,
          relations: relations
        )
      end

      private

      def extract_opinions_in_parallel(comments)
        total = comments.size
        mutex = Mutex.new
        processed = 0

        Parallel.map(comments, in_threads: config.workers) do |comment|
          result = extract_arguments_from_comment(comment)
          current = mutex.synchronize { processed += 1 }
          notify_progress(current: current, total: total)
          result
        end
      end

      def extract_arguments_from_comment(comment)
        return [] if comment[:body].nil? || comment[:body].strip.empty?

        response = llm_client.chat(
          system: config.prompts[:extraction],
          user: comment[:body],
          json_mode: true
        )
        parse_extraction_response(response)
      rescue StandardError => e
        warn "Failed to extract from comment #{comment[:id]}: #{e.message}"
        []
      end

      def parse_extraction_response(response)
        parsed = JSON.parse(response)
        opinions = parsed["extractedOpinionList"] || parsed["opinions"] || []
        opinions.select { |o| o.is_a?(String) && !o.strip.empty? }
      rescue JSON::ParserError
        parse_fallback_response(response)
      end

      def parse_fallback_response(response)
        response.split("\n").map(&:strip).reject(&:empty?)
      end

      def build_arguments_and_relations(comments, results)
        arguments = []
        relations = []

        results.each_with_index do |extracted_opinions, idx|
          comment = comments[idx]
          extracted_opinions.each_with_index do |opinion_text, opinion_idx|
            arg_id = generate_arg_id(comment[:id], opinion_idx)
            arguments << {
              arg_id: arg_id,
              argument: opinion_text,
              comment_id: comment[:id]
            }
            relations << {
              arg_id: arg_id,
              comment_id: comment[:id],
              proposal_id: comment[:proposal_id]
            }
          end
        end

        [arguments, relations]
      end

      def generate_arg_id(comment_id, index)
        "A#{comment_id}_#{index}"
      end
    end
  end
end
