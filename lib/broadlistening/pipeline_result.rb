# frozen_string_literal: true

module Broadlistening
  # Represents the final pipeline result output.
  #
  # This is the top-level structure of hierarchical_result.json,
  # compatible with Kouchou-AI.
  #
  # @example
  #   result = PipelineResult.new(
  #     arguments: [ResultArgument.new(...)],
  #     clusters: [ResultCluster.root(10), ResultCluster.new(...)],
  #     comments: { "1" => ResultComment.new(comment: "...") },
  #     property_map: { "category" => { "A1_0" => "環境" } },
  #     translations: {},
  #     overview: "全体の概要...",
  #     config: { model: "gpt-4o-mini", ... },
  #     comment_num: 100
  #   )
  PipelineResult = Data.define(
    :arguments,
    :clusters,
    :comments,
    :property_map,
    :translations,
    :overview,
    :config,
    :comment_num
  ) do
    # Convert to hash for JSON serialization
    #
    # Uses camelCase keys to match Kouchou-AI format.
    #
    # @return [Hash{Symbol => Object}]
    def to_h
      {
        arguments: arguments.map(&:to_h),
        clusters: clusters.sort_by { |c| [ c.level, c.id ] }.map(&:to_h),
        comments: comments.transform_values(&:to_h),
        propertyMap: property_map,
        translations: translations,
        overview: overview,
        config: config,
        comment_num: comment_num
      }
    end

    # Convert to JSON string
    #
    # @return [String]
    def to_json(*args)
      to_h.to_json(*args)
    end
  end
end
