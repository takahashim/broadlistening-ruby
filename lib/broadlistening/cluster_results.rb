# frozen_string_literal: true

module Broadlistening
  # Manages hierarchical cluster assignments for arguments.
  #
  # Stores the mapping of argument indices to cluster numbers at each hierarchy level.
  # Level 1 is the finest granularity, higher levels are coarser.
  #
  # @example
  #   results = ClusterResults.new
  #   results.set(1, 0, 5)   # Argument 0 belongs to cluster 5 at level 1
  #   results.set(1, 1, 5)   # Argument 1 belongs to cluster 5 at level 1
  #   results.cluster_at(1, 0)  # => 5
  #   results.unique_clusters(1)  # => [5]
  class ClusterResults
    def initialize
      @data = {}
    end

    # Get all levels, sorted ascending
    #
    # @return [Array<Integer>]
    def levels
      @data.keys.sort
    end

    # Get the maximum level
    #
    # @return [Integer, nil]
    def max_level
      @data.keys.max
    end

    # Check if empty
    #
    # @return [Boolean]
    def empty?
      @data.empty?
    end

    # Get cluster number for an argument at a level
    #
    # @param level [Integer]
    # @param arg_index [Integer]
    # @return [Integer, nil]
    def cluster_at(level, arg_index)
      @data.dig(level, arg_index)
    end

    # Set cluster number for an argument at a level
    #
    # @param level [Integer]
    # @param arg_index [Integer]
    # @param cluster_num [Integer]
    def set(level, arg_index, cluster_num)
      @data[level] ||= []
      @data[level][arg_index] = cluster_num
    end

    # Get unique cluster numbers at a level
    #
    # @param level [Integer]
    # @return [Array<Integer>]
    def unique_clusters(level)
      @data[level]&.compact&.uniq || []
    end

    # Get all cluster numbers at a level (raw array access)
    #
    # @param level [Integer]
    # @return [Array<Integer>, nil]
    def [](level)
      @data[level]
    end

    # Iterate over each level
    #
    # @yield [level, clusters] Each level and its cluster array
    def each_level(&block)
      @data.keys.sort.each do |level|
        block.call(level, @data[level])
      end
    end

    # Get all cluster arrays (for backward compatibility)
    #
    # @return [Array<Array<Integer>>]
    def values
      @data.values
    end

    # Get all level keys (for backward compatibility)
    #
    # @return [Array<Integer>]
    def keys
      @data.keys
    end

    # Convert to hash for serialization
    #
    # @return [Hash{Integer => Array<Integer>}]
    def to_h
      @data.dup
    end

    # Build from hash (for loading)
    #
    # @param hash [Hash{Integer => Array<Integer>}]
    # @return [ClusterResults]
    def self.from_h(hash)
      results = new
      hash.each do |level, clusters|
        clusters.each_with_index do |cluster_num, idx|
          results.set(level, idx, cluster_num) if cluster_num
        end
      end
      results
    end
  end
end
