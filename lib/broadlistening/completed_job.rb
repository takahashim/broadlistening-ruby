# frozen_string_literal: true

require "digest"

module Broadlistening
  # Threshold for hashing long string parameters in CompletedJob
  LONG_STRING_THRESHOLD = 100

  # Represents a completed pipeline job/step.
  #
  # CompletedJob is an immutable value object that records the execution
  # details of a completed pipeline step.
  #
  # @example Creating a completed job
  #   job = CompletedJob.create(
  #     step: :extraction,
  #     duration: 30.5,
  #     params: { model: "gpt-4o-mini" },
  #     token_usage: 1500
  #   )
  CompletedJob = Data.define(:step, :completed, :duration, :params, :token_usage) do
    # Create a CompletedJob with automatic timestamp and params serialization
    #
    # @param step [Symbol, String] Step name
    # @param duration [Float] Duration in seconds
    # @param params [Hash] Step parameters (long strings will be hashed)
    # @param token_usage [Integer] Token usage count
    # @return [CompletedJob]
    def self.create(step:, duration:, params:, token_usage: 0)
      new(
        step: step.to_s,
        completed: Time.now.iso8601,
        duration: duration,
        params: serialize_params(params),
        token_usage: token_usage
      )
    end

    # Create a CompletedJob from a hash (for deserialization)
    #
    # @param hash [Hash] Input hash with job data
    # @return [CompletedJob]
    def self.from_hash(hash)
      raw_params = hash[:params] || hash["params"] || {}
      new(
        step: hash[:step]&.to_s || hash["step"]&.to_s,
        completed: hash[:completed] || hash["completed"],
        duration: hash[:duration] || hash["duration"],
        params: normalize_params_keys(raw_params),
        token_usage: hash[:token_usage] || hash["token_usage"] || 0
      )
    end

    # Normalize params keys to symbols
    #
    # @param params [Hash] Params with string or symbol keys
    # @return [Hash] Params with symbol keys
    def self.normalize_params_keys(params)
      params.transform_keys(&:to_sym)
    end

    # Serialize params, hashing long strings for storage efficiency
    #
    # @param params [Hash] Raw parameters
    # @return [Hash] Serialized parameters
    def self.serialize_params(params)
      params.transform_values do |v|
        if v.is_a?(String) && v.length > LONG_STRING_THRESHOLD
          Digest::SHA256.hexdigest(v)
        else
          v
        end
      end
    end

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
  end
end
