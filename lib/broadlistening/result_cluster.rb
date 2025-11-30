# frozen_string_literal: true

module Broadlistening
  # Represents a cluster in the pipeline result output.
  #
  # This is the output format for clusters in hierarchical_result.json,
  # compatible with Kouchou-AI.
  #
  # @example
  #   cluster = ResultCluster.new(
  #     level: 1,
  #     id: "1_0",
  #     label: "環境問題",
  #     takeaway: "環境に関する意見のグループ",
  #     value: 25,
  #     parent: "0",
  #     density_rank_percentile: 0.75
  #   )
  ResultCluster = Data.define(
    :level,
    :id,
    :label,
    :takeaway,
    :value,
    :parent,
    :density_rank_percentile
  ) do
    # Create the root cluster
    #
    # @param argument_count [Integer] Total number of arguments
    # @return [ResultCluster]
    def self.root(argument_count)
      new(
        level: 0,
        id: "0",
        label: "全体",
        takeaway: "",
        value: argument_count,
        parent: "",
        density_rank_percentile: nil
      )
    end

    # Convert to hash for JSON serialization
    #
    # @return [Hash{Symbol => Object}]
    def to_h
      {
        level: level,
        id: id,
        label: label,
        takeaway: takeaway,
        value: value,
        parent: parent,
        density_rank_percentile: density_rank_percentile
      }
    end
  end
end
