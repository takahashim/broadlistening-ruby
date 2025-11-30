# frozen_string_literal: true

module Broadlistening
  # Represents a comment in the pipeline result output.
  #
  # This is the output format for comments in hierarchical_result.json,
  # compatible with Kouchou-AI.
  #
  # @example
  #   comment = ResultComment.new(comment: "I think we need more parks in the city.")
  ResultComment = Data.define(:comment) do
    # Convert to hash for JSON serialization
    #
    # @return [Hash{Symbol => String}]
    def to_h
      { comment: comment }
    end
  end
end
