# frozen_string_literal: true

module Broadlistening
  # Represents an extracted argument (opinion) from a comment.
  #
  # Arguments are created during the extraction step and enriched through
  # subsequent pipeline steps (embedding, clustering).
  #
  # @example Creating an argument
  #   arg = Argument.new(arg_id: "A1_0", argument: "We need more parks", comment_id: "1")
  #   arg.embedding = [0.1, 0.2, 0.3]  # Added by embedding step
  #   arg.x = 0.5                       # Added by clustering step
  class Argument
    attr_accessor :arg_id, :argument, :comment_id,
                  :embedding, :x, :y, :cluster_ids,
                  :attributes, :url, :properties

    def initialize(
      arg_id:,
      argument:,
      comment_id:,
      embedding: nil,
      x: nil,
      y: nil,
      cluster_ids: nil,
      attributes: nil,
      url: nil,
      properties: nil
    )
      @arg_id = arg_id
      @argument = argument
      @comment_id = comment_id
      @embedding = embedding
      @x = x
      @y = y
      @cluster_ids = cluster_ids
      @attributes = attributes
      @url = url
      @properties = properties
    end

    # Create an Argument from a hash
    #
    # @param hash [Hash] Input hash with argument data
    # @return [Argument]
    def self.from_hash(hash)
      new(
        arg_id: hash[:arg_id] || hash["arg_id"],
        argument: hash[:argument] || hash["argument"],
        comment_id: hash[:comment_id] || hash["comment_id"],
        embedding: hash[:embedding] || hash["embedding"],
        x: hash[:x] || hash["x"],
        y: hash[:y] || hash["y"],
        cluster_ids: hash[:cluster_ids] || hash["cluster_ids"],
        attributes: hash[:attributes] || hash["attributes"],
        url: hash[:url] || hash["url"],
        properties: hash[:properties] || hash["properties"]
      )
    end

    # Create an Argument from a Comment during extraction
    #
    # @param comment [Comment] Source comment
    # @param opinion_text [String] Extracted opinion text
    # @param index [Integer] Opinion index within the comment
    # @return [Argument]
    def self.from_comment(comment, opinion_text, index)
      new(
        arg_id: "A#{comment.id}_#{index}",
        argument: opinion_text,
        comment_id: comment.id,
        attributes: comment.attributes,
        url: comment.source_url,
        properties: comment.properties
      )
    end

    # Convert to hash for serialization
    #
    # @return [Hash]
    def to_h
      {
        arg_id: @arg_id,
        argument: @argument,
        comment_id: @comment_id,
        embedding: @embedding,
        x: @x,
        y: @y,
        cluster_ids: @cluster_ids,
        attributes: @attributes,
        url: @url,
        properties: @properties
      }.compact
    end

    # Convert to hash with only embedding data (for embeddings.json)
    #
    # @return [Hash]
    def to_embedding_h
      {
        arg_id: @arg_id,
        embedding: @embedding
      }
    end

    # Convert to hash with only clustering data (for clustering.json)
    #
    # @return [Hash]
    def to_clustering_h
      {
        arg_id: @arg_id,
        x: @x,
        y: @y,
        cluster_ids: @cluster_ids
      }
    end

    # Check if argument belongs to a specific cluster
    #
    # @param cluster_id [String] Cluster ID to check
    # @return [Boolean]
    def in_cluster?(cluster_id)
      @cluster_ids&.include?(cluster_id) || false
    end

    # Extract numeric comment_id from arg_id if comment_id is not set
    #
    # @return [Integer]
    def comment_id_int
      return @comment_id.to_i if @comment_id

      match = @arg_id&.match(/\AA(\d+)_/)
      match ? match[1].to_i : 0
    end
  end
end
