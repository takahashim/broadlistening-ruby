# frozen_string_literal: true

module Broadlistening
  # Represents the final pipeline result output.
  #
  # This is the top-level structure of hierarchical_result.json,
  # compatible with Kouchou-AI.
  #
  # @example
  #   result = PipelineResult.new(
  #     arguments: [PipelineResult::Argument.new(...)],
  #     clusters: [PipelineResult::Cluster.root(10), PipelineResult::Cluster.new(...)],
  #     comments: { "1" => PipelineResult::Comment.new(comment: "...") },
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

  # Represents an argument in the pipeline result output.
  #
  # This is the output format for arguments in hierarchical_result.json,
  # compatible with Kouchou-AI.
  #
  # @example
  #   arg = PipelineResult::Argument.new(
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
  PipelineResult::Argument = Data.define(
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

  # Represents a cluster in the pipeline result output.
  #
  # This is the output format for clusters in hierarchical_result.json,
  # compatible with Kouchou-AI.
  #
  # @example
  #   cluster = PipelineResult::Cluster.new(
  #     level: 1,
  #     id: "1_0",
  #     label: "環境問題",
  #     takeaway: "環境に関する意見のグループ",
  #     value: 25,
  #     parent: "0",
  #     density_rank_percentile: 0.75
  #   )
  PipelineResult::Cluster = Data.define(
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
    # @return [PipelineResult::Cluster]
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

  # Represents a comment in the pipeline result output.
  #
  # This is the output format for comments in hierarchical_result.json,
  # compatible with Kouchou-AI.
  #
  # @example
  #   comment = PipelineResult::Comment.new(comment: "I think we need more parks in the city.")
  PipelineResult::Comment = Data.define(:comment) do
    # Convert to hash for JSON serialization
    #
    # @return [Hash{Symbol => String}]
    def to_h
      { comment: comment }
    end
  end
end
