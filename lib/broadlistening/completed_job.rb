# frozen_string_literal: true

module Broadlistening
  # Represents a completed pipeline job/step.
  #
  # CompletedJob is an immutable value object that records the execution
  # details of a completed pipeline step.
  #
  # @example Creating a completed job
  #   job = CompletedJob.new(
  #     step: "extraction",
  #     completed: "2024-01-01T12:00:00+09:00",
  #     duration: 30.5,
  #     params: { model: "gpt-4o-mini" },
  #     token_usage: 1500
  #   )
  CompletedJob = Data.define(:step, :completed, :duration, :params, :token_usage) do
    # Convert to hash for serialization
    #
    # @return [Hash{Symbol => String | Float | Hash | Integer}]
    def to_h
      {
        step: step,
        completed: completed,
        duration: duration,
        params: params,
        token_usage: token_usage
      }
    end

    # Create a CompletedJob from a hash
    #
    # @param hash [Hash] Input hash with job data
    # @return [CompletedJob]
    def self.from_hash(hash)
      new(
        step: hash[:step]&.to_s || hash["step"]&.to_s,
        completed: hash[:completed] || hash["completed"],
        duration: hash[:duration] || hash["duration"],
        params: hash[:params] || hash["params"] || {},
        token_usage: hash[:token_usage] || hash["token_usage"] || 0
      )
    end
  end
end
