# frozen_string_literal: true

module Broadlistening
  # Represents an argument in the pipeline result output.
  #
  # This is the output format for arguments in hierarchical_result.json,
  # compatible with Kouchou-AI.
  #
  # @example
  #   arg = ResultArgument.new(
  #     arg_id: "A1_0",
  #     argument: "We need more parks",
  #     comment_id: 1,
  #     x: 0.5,
  #     y: -0.3,
  #     p: 0,
  #     cluster_ids: ["0", "1_0", "2_1"],
  #     attributes: { "age" => "30代" },
  #     url: "https://example.com/comment/1"
  #   )
  ResultArgument = Data.define(
    :arg_id,
    :argument,
    :comment_id,
    :x,
    :y,
    :p,
    :cluster_ids,
    :attributes,
    :url
  ) do
    # Convert to hash for JSON serialization
    #
    # @return [Hash{Symbol => Object}]
    def to_h
      result = {
        arg_id: arg_id,
        argument: argument,
        comment_id: comment_id,
        x: x,
        y: y,
        p: p,
        cluster_ids: cluster_ids
      }
      result[:attributes] = attributes if attributes
      result[:url] = url if url
      result
    end
  end
end
