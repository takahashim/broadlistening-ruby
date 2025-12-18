# frozen_string_literal: true

module Broadlistening
  # Represents the relationship between an Argument and its source Comment.
  #
  # @example
  #   relation = Relation.new(arg_id: "A1_0", comment_id: "1")
  Relation = Data.define(:arg_id, :comment_id) do
    # Convert to hash for serialization
    #
    # @return [Hash{Symbol => String}]
    def to_h
      { arg_id: arg_id, comment_id: comment_id }
    end
  end
end
