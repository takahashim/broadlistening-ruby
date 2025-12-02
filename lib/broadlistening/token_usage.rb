# frozen_string_literal: true

module Broadlistening
  # Tracks token usage from LLM API calls.
  # Compatible with Python kouchou-ai's token tracking.
  class TokenUsage
    attr_accessor :input, :output, :total

    def initialize(input: 0, output: 0, total: nil)
      @input = input
      @output = output
      @total = total || (input + output)
    end

    def add(other)
      return self unless other

      @input += other.input
      @output += other.output
      @total += other.total
      self
    end

    def +(other)
      dup.add(other)
    end

    def to_h
      { input: @input, output: @output, total: @total }
    end

    def zero?
      @total.zero?
    end

    def dup
      TokenUsage.new(input: @input, output: @output, total: @total)
    end

    def self.from_response(response)
      usage = response.dig("usage") || {}
      new(
        input: usage["prompt_tokens"] || 0,
        output: usage["completion_tokens"] || 0,
        total: usage["total_tokens"]
      )
    end
  end
end
