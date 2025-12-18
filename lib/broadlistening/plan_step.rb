# frozen_string_literal: true

module Broadlistening
  # Represents a step in the execution plan.
  #
  # @example
  #   step = PlanStep.new(step: :extraction, run: true, reason: "no trace of previous run")
  #   step.run?  # => true
  PlanStep = Data.define(:step, :run, :reason) do
    # Whether this step should be executed
    #
    # @return [Boolean]
    def run?
      run
    end

    # Convert to hash for serialization
    #
    # @return [Hash{Symbol => Object}]
    def to_h
      { step: step.to_s, run: run, reason: reason }
    end
  end
end
