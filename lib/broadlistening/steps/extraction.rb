# frozen_string_literal: true

module Broadlistening
  module Steps
    class Extraction < BaseStep
      def execute
        return context if context.comments.empty?

        comments = apply_limit(context.comments)
        results = extract_opinions_in_parallel(comments)
        build_arguments_and_relations(comments, results)

        context
      end

      private

      def apply_limit(comments)
        return comments if config.limit.nil? || config.limit <= 0

        comments.first(config.limit)
      end

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
        return [] if comment.empty?

        result = llm_client.chat(
          system: config.prompts[:extraction],
          user: comment.body,
          json_mode: true
        )
        context.add_token_usage(result.token_usage)
        parse_extraction_response(result.content)
      rescue StandardError => e
        warn "Failed to extract from comment #{comment.id}: #{e.message}"
        []
      end

      def parse_extraction_response(content)
        parsed = JSON.parse(content)

        # Handle dict response (structured output)
        if parsed.is_a?(Hash)
          opinions = parsed["extractedOpinionList"] || parsed["opinions"] || []
          return opinions.select { |o| o.is_a?(String) && !o.strip.empty? }
        end

        # Handle string response (single opinion)
        if parsed.is_a?(String)
          return [ parsed.strip ].reject(&:empty?)
        end

        # Handle array response
        if parsed.is_a?(Array)
          return parsed.select { |o| o.is_a?(String) && !o.strip.empty? }.map(&:strip)
        end

        []
      rescue JSON::ParserError
        parse_fallback_response(content)
      end

      def parse_fallback_response(content)
        return [] if content.nil? || content.strip.empty?

        cleaned = content.gsub(/```json\s*/i, "").gsub(/```\s*/, "")

        # Try to extract JSON array using balanced bracket matching
        json_str = extract_balanced_json_array(cleaned)
        if json_str
          # Fix trailing commas before ]
          json_str = json_str.gsub(/,\s*\]/, "]")

          begin
            parsed = JSON.parse(json_str)
            if parsed.is_a?(Array)
              return parsed.select { |o| o.is_a?(String) }.map(&:strip).reject(&:empty?)
            end
          rescue JSON::ParserError
            # Fall through to line-based parsing
          end
        end

        content.split("\n").map(&:strip).reject(&:empty?)
      end

      # Extract a balanced JSON array from text (handles nested arrays)
      def extract_balanced_json_array(text)
        start_idx = text.index("[")
        return nil unless start_idx

        depth = 0
        in_string = false
        escape_next = false

        (start_idx...text.length).each do |i|
          char = text[i]

          if escape_next
            escape_next = false
            next
          end

          if char == "\\"
            escape_next = true
            next
          end

          if char == '"'
            in_string = !in_string
            next
          end

          next if in_string

          if char == "["
            depth += 1
          elsif char == "]"
            depth -= 1
            return text[start_idx..i] if depth == 0
          end
        end

        nil # Unbalanced brackets
      end

      def build_arguments_and_relations(comments, results)
        results.each_with_index do |extracted_opinions, idx|
          comment = comments[idx]
          extracted_opinions.each_with_index do |opinion_text, opinion_idx|
            arg = Argument.from_comment(comment, opinion_text, opinion_idx)
            context.arguments << arg

            context.relations << Relation.new(
              arg_id: arg.arg_id,
              comment_id: arg.comment_id
            )
          end
        end
      end
    end
  end
end
