# frozen_string_literal: true

require "pathname"
require "fileutils"
require "json"

module Broadlistening
  # Manages pipeline execution context - all data flowing through the pipeline.
  #
  # The Context holds all intermediate results and provides methods for
  # loading from / saving to disk for incremental execution support.
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

    # Output file mapping for each step
    OUTPUT_FILES = {
      extraction: "extraction.json",
      embedding: "embeddings.json",
      clustering: "clustering.json",
      initial_labelling: "initial_labels.json",
      merge_labelling: "merge_labels.json",
      overview: "overview.json",
      aggregation: "result.json"
    }.freeze

    # Load existing context from output directory
    #
    # @param output_dir [String, Pathname] Directory containing output files
    # @return [Context] A new context populated with data from output files
    def self.load_from_dir(output_dir)
      context = new
      dir = Pathname.new(output_dir)

      OUTPUT_FILES.each do |step, filename|
        file = dir / filename
        next unless file.exist?

        data = JSON.parse(file.read, symbolize_names: true)
        context.send(:merge_step_data, step, data)
      end

      context
    end

    def initialize
      @comments = []
      @arguments = []
      @relations = []
      @cluster_results = {}
      @umap_coords = nil
      @initial_labels = {}
      @labels = {}
      @overview = nil
      @result = nil
      @output_dir = nil
      @token_usage = TokenUsage.new
    end

    def add_token_usage(usage)
      @token_usage.add(usage) if usage
    end

    # Save a step's output to file
    #
    # @param step_name [Symbol] The step name
    # @param output_dir [String, Pathname] Output directory
    def save_step(step_name, output_dir)
      dir = Pathname.new(output_dir)
      filename = OUTPUT_FILES[step_name]
      return unless filename

      FileUtils.mkdir_p(dir)
      data = extract_step_output(step_name)
      File.write(dir / filename, JSON.pretty_generate(data))
    end

    # Convert to hash for serialization
    #
    # @return [Hash]
    def to_h
      {
        comments: @comments.map(&:to_h),
        arguments: @arguments.map(&:to_h),
        relations: @relations,
        cluster_results: @cluster_results,
        umap_coords: @umap_coords,
        initial_labels: @initial_labels,
        labels: @labels,
        overview: @overview,
        result: @result
      }
    end

    private

    def extract_step_output(step_name)
      case step_name
      when :extraction
        {
          comments: @comments.map(&:to_h),
          arguments: @arguments.map(&:to_h),
          relations: @relations
        }
      when :embedding
        {
          arguments: @arguments.map(&:to_embedding_h)
        }
      when :clustering
        {
          cluster_results: @cluster_results,
          arguments: @arguments.map(&:to_clustering_h)
        }
      when :initial_labelling
        { initial_labels: serialize_labels(@initial_labels) }
      when :merge_labelling
        { labels: serialize_labels(@labels) }
      when :overview
        { overview: @overview }
      when :aggregation
        @result&.to_h
      end
    end

    def merge_step_data(step_name, data)
      case step_name
      when :extraction
        load_extraction_data(data)
      when :embedding
        merge_embedding_data(data)
      when :clustering
        merge_clustering_data(data)
      when :initial_labelling
        @initial_labels = load_labels_hash(data[:initial_labels]) if data[:initial_labels]
      when :merge_labelling
        @labels = load_labels_hash(data[:labels]) if data[:labels]
      when :overview
        @overview = data[:overview] if data[:overview]
      end
    end

    def load_extraction_data(data)
      @comments = (data[:comments] || []).map do |c|
        Comment.new(**c.slice(:id, :body, :proposal_id, :source_url, :attributes, :properties))
      end
      @arguments = (data[:arguments] || []).map { |a| Argument.from_hash(a) }
      @relations = data[:relations] if data[:relations]
    end

    def merge_embedding_data(data)
      return unless data[:arguments]

      embedding_map = data[:arguments].to_h { |e| [ e[:arg_id], e[:embedding] ] }
      @arguments.each do |arg|
        embedding = embedding_map[arg.arg_id]
        arg.embedding = embedding if embedding
      end
    end

    def merge_clustering_data(data)
      @cluster_results = data[:cluster_results] if data[:cluster_results]
      return unless data[:arguments]

      clustering_map = data[:arguments].to_h { |c| [ c[:arg_id], c ] }
      @arguments.each do |arg|
        cluster_data = clustering_map[arg.arg_id]
        next unless cluster_data

        arg.x = cluster_data[:x]
        arg.y = cluster_data[:y]
        arg.cluster_ids = cluster_data[:cluster_ids]
      end
    end

    def load_labels_hash(labels_data)
      labels_data.transform_values do |label_hash|
        ClusterLabel.from_hash(label_hash)
      end
    end

    def serialize_labels(labels)
      labels.transform_values(&:to_h)
    end
  end
end
