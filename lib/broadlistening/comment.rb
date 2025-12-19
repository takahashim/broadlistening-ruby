# frozen_string_literal: true

module Broadlistening
  # Represents a normalized comment in the pipeline.
  #
  # Comments are the input data to the pipeline, containing user opinions
  # that will be processed into arguments through the extraction step.
  #
  # @example Creating from a hash
  #   comment = Comment.from_hash({ id: "1", body: "I think...", attribute_age: "30代" })
  #   comment.id        # => "1"
  #   comment.body      # => "I think..."
  #   comment.attributes # => { "age" => "30代" }
  class Comment
    attr_accessor :id, :body, :proposal_id, :source_url, :source, :url, :attributes, :properties

    def initialize(id:, body:, proposal_id: nil, source_url: nil, source: nil, url: nil, attributes: nil, properties: nil)
      @id = id
      @body = body
      @proposal_id = proposal_id
      @source_url = source_url
      @source = source
      @url = url
      @attributes = attributes
      @properties = properties
    end

    # Create a Comment from a hash, normalizing various input formats
    #
    # @param hash [Hash] Input hash with comment data
    # @param property_names [Array<String>] Property names to extract (from config)
    # @return [Comment]
    def self.from_hash(hash, property_names: [])
      new(
        id: hash[:id] || hash["id"],
        body: hash[:body] || hash["body"],
        proposal_id: hash[:proposal_id] || hash["proposal_id"],
        source_url: extract_source_url(hash),
        source: hash[:source] || hash["source"],
        url: hash[:url] || hash["url"],
        attributes: extract_attributes(hash),
        properties: extract_properties(hash, property_names)
      )
    end

    # Create a Comment from an object (e.g., ActiveRecord model)
    #
    # @param obj [Object] Object responding to id, body, etc.
    # @param property_names [Array<String>] Property names to extract
    # @return [Comment]
    def self.from_object(obj, property_names: [])
      new(
        id: obj.id,
        body: obj.body,
        proposal_id: obj.respond_to?(:proposal_id) ? obj.proposal_id : nil,
        source_url: obj.respond_to?(:source_url) ? obj.source_url : nil,
        attributes: extract_attributes_from_object(obj),
        properties: extract_properties_from_object(obj, property_names)
      )
    end

    # Convert to hash for serialization
    #
    # @return [Hash]
    def to_h
      {
        id: @id,
        body: @body,
        proposal_id: @proposal_id,
        source_url: @source_url,
        source: @source,
        url: @url,
        attributes: @attributes,
        properties: @properties
      }
    end

    # Check if comment body is empty or nil
    #
    # @return [Boolean]
    def empty?
      @body.nil? || @body.strip.empty?
    end

    class << self
      private

      def extract_source_url(hash)
        hash[:source_url] || hash["source_url"] ||
          hash[:"source-url"] || hash["source-url"]
      end

      def extract_attributes(hash)
        attributes = {}
        hash.each do |key, value|
          key_str = key.to_s
          next unless key_str.start_with?("attribute_") || key_str.start_with?("attribute-")

          attr_name = key_str.sub(/^attribute[-_]/, "")
          attributes[attr_name] = value
        end
        attributes.empty? ? nil : attributes
      end

      def extract_attributes_from_object(obj)
        return nil unless obj.respond_to?(:attributes) && obj.attributes.is_a?(Hash)

        obj.attributes.empty? ? nil : obj.attributes
      end

      def extract_properties(hash, property_names)
        return nil if property_names.empty?

        properties = {}
        property_names.each do |prop_name|
          value = hash[prop_name.to_sym] || hash[prop_name.to_s]
          properties[prop_name.to_s] = value
        end
        properties.values.all?(&:nil?) ? nil : properties
      end

      def extract_properties_from_object(obj, property_names)
        return nil if property_names.empty?

        properties = {}
        property_names.each do |prop_name|
          value = obj.respond_to?(prop_name) ? obj.public_send(prop_name) : nil
          properties[prop_name.to_s] = value
        end
        properties.values.all?(&:nil?) ? nil : properties
      end
    end
  end
end
