# frozen_string_literal: true

# Helper module for extracting JSON from LLM responses that may contain extra text.
# Some models (e.g., gpt-oss-120b) add prefixes like "JSON.", "**{", ".{", etc.
module JsonExtractor
  module_function

  def extract_json(text)
    # Try parsing directly first
    return text if valid_json?(text)

    # Remove markdown code blocks if present
    cleaned = text.gsub(/```(?:json)?\s*([\s\S]*?)```/, '\1').strip

    # Try parsing after markdown removal
    return cleaned if valid_json?(cleaned)

    # Find all { or [ positions and try each in order
    # This handles prefixes like ".{" by finding the first valid JSON
    start_positions = []
    cleaned.each_char.with_index do |char, idx|
      start_positions << idx if char == "{" || char == "["
    end

    start_positions.each do |pos|
      extracted = extract_balanced_json(cleaned[pos..])
      return extracted if extracted && valid_json?(extracted)
    end

    raise JSON::ParserError, "No valid JSON found in: #{text[0..100]}"
  end

  def extract_balanced_json(text)
    return nil if text.nil? || text.empty?

    opener = text[0]
    closer = opener == "{" ? "}" : "]"
    depth = 0
    end_idx = nil
    in_string = false
    escape_next = false

    text.each_char.with_index do |char, idx|
      if escape_next
        escape_next = false
        next
      end

      if char == "\\"
        escape_next = true
        next
      end

      if char == '"' && !escape_next
        in_string = !in_string
        next
      end

      next if in_string

      depth += 1 if char == opener
      depth -= 1 if char == closer
      if depth == 0
        end_idx = idx
        break
      end
    end

    return nil unless end_idx

    text[0..end_idx]
  end

  def valid_json?(text)
    return false if text.nil? || text.empty?

    JSON.parse(text)
    true
  rescue JSON::ParserError
    false
  end
end
