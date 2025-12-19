# frozen_string_literal: true

module Broadlistening
  # Manages pipeline execution context - all data flowing through the pipeline.
  #
  # The Context holds all intermediate results. File I/O is handled by
  # Context::Loader and Context::Serializer.
  #
  # @example Creating a new context
  #   context = Context.new
  #   context.comments = [Comment.new(...), ...]
  #   context.save_step(:extraction, output_dir)
  #
  # @example Loading from existing output
  #   context = Context.load_from_dir("/path/to/output")
  class Context
    attr_accessor :comments, :arguments, :relations,
                  :cluster_results, :umap_coords,
                  :initial_labels, :labels, :overview, :result,
                  :output_dir, :token_usage

    # Output file mapping for each step (Python-compatible format)
    OUTPUT_FILES = {
      extraction: { args: "args.csv", relations: "relations.csv" },
      embedding: "embeddings.json",
      clustering: "hierarchical_clusters.csv",
      initial_labelling: "hierarchical_initial_labels.csv",
      merge_labelling: "hierarchical_merge_labels.csv",
      overview: "hierarchical_overview.txt",
      aggregation: "hierarchical_result.json"
    }.freeze

    # Load existing context from output directory
    #
    # @param output_dir [String, Pathname] Directory containing output files
    # @return [Context] A new context populated with data from output files
    def self.load_from_dir(output_dir)
      context = new
      Loader.load_from_dir(context, output_dir)
      context
    end

    def initialize(
      comments: [],
      arguments: [],
      relations: [],
      cluster_results: nil,
      umap_coords: nil,
      initial_labels: {},
      labels: {},
      overview: nil,
      result: nil,
      output_dir: nil,
      token_usage: nil
    )
      @comments = comments
      @arguments = arguments
      @relations = relations
      @cluster_results = cluster_results || ClusterResults.new
      @umap_coords = umap_coords
      @initial_labels = initial_labels
      @labels = labels
      @overview = overview
      @result = result
      @output_dir = output_dir
      @token_usage = token_usage || TokenUsage.new
    end

    def add_token_usage(usage)
      @token_usage.add(usage) if usage
    end

    # Save a step's output to file
    #
    # @param step_name [Symbol] The step name
    # @param output_dir [String, Pathname] Output directory
    def save_step(step_name, output_dir)
      Serializer.save_step(self, step_name, output_dir)
    end

    # Convert to hash for serialization
    #
    # @return [Hash]
    def to_h
      {
        comments: @comments.map(&:to_h),
        arguments: @arguments.map(&:to_h),
        relations: @relations.map(&:to_h),
        cluster_results: @cluster_results.to_h,
        umap_coords: @umap_coords,
        initial_labels: serialize_labels(@initial_labels),
        labels: serialize_labels(@labels),
        overview: @overview,
        result: @result
      }
    end

    private

    def serialize_labels(labels_hash)
      labels_hash.transform_values(&:to_h)
    end
  end
end
