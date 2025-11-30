# frozen_string_literal: true

module Broadlistening
  # Represents a label for a cluster.
  #
  # ClusterLabel is an immutable value object that holds the label and description
  # for a cluster at a specific level in the hierarchy.
  #
  # @example Creating a cluster label
  #   label = ClusterLabel.new(
  #     cluster_id: "1_0",
  #     level: 1,
  #     label: "環境問題",
  #     description: "環境に関する意見のグループ"
  #   )
  #   label.cluster_id  # => "1_0"
  #   label.to_h        # => {cluster_id: "1_0", level: 1, ...}
  ClusterLabel = Data.define(:cluster_id, :level, :label, :description) do
    # Convert to hash for serialization
    #
    # @return [Hash{Symbol => String | Integer}]
    def to_h
      {
        cluster_id: cluster_id,
        level: level,
        label: label,
        description: description
      }
    end

    # Create a ClusterLabel from a hash
    #
    # @param hash [Hash] Input hash with label data
    # @return [ClusterLabel]
    def self.from_hash(hash)
      new(
        cluster_id: hash[:cluster_id] || hash["cluster_id"],
        level: hash[:level] || hash["level"],
        label: hash[:label] || hash["label"],
        description: hash[:description] || hash["description"] || ""
      )
    end

    # Create a default label for a cluster
    #
    # @param level [Integer] The cluster level
    # @param cluster_num [Integer] The cluster number within the level
    # @return [ClusterLabel]
    def self.default(level, cluster_num)
      new(
        cluster_id: "#{level}_#{cluster_num}",
        level: level,
        label: "グループ#{cluster_num}",
        description: ""
      )
    end
  end
end
