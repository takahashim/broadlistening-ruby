# frozen_string_literal: true

module Broadlistening
  # Represents cluster information during hierarchical clustering.
  #
  # ClusterInfo is an immutable value object that holds the centroid,
  # size, and member information for a cluster during Ward's method
  # hierarchical merging.
  #
  # @example Creating cluster info
  #   info = ClusterInfo.new(
  #     centroid: [0.5, 0.3],
  #     size: 10,
  #     members: [0, 1, 2]
  #   )
  ClusterInfo = Data.define(:centroid, :size, :members) do
    # Merge two clusters using Ward's method
    #
    # @param other [ClusterInfo] The other cluster to merge with
    # @return [ClusterInfo] A new merged cluster
    def merge_with(other)
      new_size = size + other.size
      new_centroid = centroid.zip(other.centroid).map do |v1, v2|
        (v1 * size + v2 * other.size) / new_size
      end
      new_members = members + other.members

      ClusterInfo.new(
        centroid: new_centroid,
        size: new_size,
        members: new_members
      )
    end

    # Calculate Ward distance to another cluster
    #
    # @param other [ClusterInfo] The other cluster
    # @return [Float] Ward distance
    def ward_distance_to(other)
      dist_sq = centroid.zip(other.centroid).sum { |a, b| (a - b)**2 }
      Math.sqrt(2.0 * size * other.size / (size + other.size) * dist_sq)
    end

    # Get the minimum member ID (used as cluster representative ID)
    #
    # @return [Integer]
    def min_member
      members.min
    end
  end
end
