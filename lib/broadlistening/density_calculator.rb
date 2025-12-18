# frozen_string_literal: true

module Broadlistening
  # Calculates cluster density based on point distribution.
  #
  # Density is calculated as 1 / (avg_distance_from_center + epsilon)
  # where avg_distance_from_center is the mean Euclidean distance from each point
  # in the cluster to the cluster's centroid.
  #
  # @example Simple density calculation
  #   density = DensityCalculator.calculate([[0, 0], [1, 0], [0, 1], [1, 1]])
  #
  # @example Calculate with ranks for multiple clusters
  #   clusters = DensityCalculator::ClusterPoints.build_from(arguments, labels)
  #   densities = DensityCalculator.calculate_with_ranks(clusters)
  #   densities["1_0"].density_rank_percentile  # => 0.5
  class DensityCalculator
    EPSILON = 1e-10

    # Represents a cluster's points for density calculation
    ClusterPoints = Data.define(:cluster_id, :points, :level) do
      # Build ClusterPoints array from arguments and labels
      #
      # @param arguments [Array<Argument>] Arguments with cluster assignments and coordinates
      # @param labels [Hash{String => ClusterLabel}] Cluster labels keyed by cluster_id
      # @return [Array<ClusterPoints>]
      def self.build_from(arguments, labels)
        labels.each_value.map do |label|
          points = arguments.filter_map do |arg|
            next unless arg.cluster_ids&.include?(label.cluster_id)
            next unless arg.x && arg.y

            [ arg.x, arg.y ]
          end
          new(cluster_id: label.cluster_id, points: points, level: label.level)
        end
      end
    end

    # Calculate density for a single cluster's points
    #
    # @param points [Array<Array<Float>>] Array of [x, y] coordinate pairs
    # @return [Float] Density value
    def self.calculate(points)
      new(points).density
    end

    # Calculate densities with ranks for multiple clusters
    #
    # @param clusters [Array<ClusterPoints>] Cluster data with points and levels
    # @return [Hash{String => DensityInfo}] cluster_id => DensityInfo
    def self.calculate_with_ranks(clusters)
      return {} if clusters.empty?

      result = {}
      clusters.group_by(&:level).each_value do |level_clusters|
        add_level_ranks(level_clusters, result)
      end
      result
    end

    # @param points [Array<Array<Float>>] Array of [x, y] coordinate pairs
    def initialize(points)
      @points = normalize(points)
    end

    # Calculate density for this cluster
    #
    # @return [Float] Density value (higher = tighter cluster)
    def density
      return 1.0 / EPSILON if @points.empty? || @points.size == 1

      center = centroid
      avg_distance = @points.sum { |x, y| distance_to(center, x, y) } / @points.size.to_f
      1.0 / (avg_distance + EPSILON)
    end

    class << self
      private

      def add_level_ranks(clusters, result)
        densities = clusters.to_h { |c| [ c.cluster_id, calculate(c.points) ] }
        sorted = densities.sort_by { |_, d| -d }.map(&:first)

        sorted.each_with_index do |cluster_id, idx|
          rank = idx + 1
          result[cluster_id] = DensityInfo.new(
            density: densities[cluster_id],
            density_rank: rank,
            density_rank_percentile: rank.to_f / sorted.size
          )
        end
      end
    end

    private

    def normalize(points)
      points.respond_to?(:to_a) && !points.is_a?(Array) ? points.to_a : points
    end

    def centroid
      [
        @points.sum { |p| p[0] } / @points.size.to_f,
        @points.sum { |p| p[1] } / @points.size.to_f
      ]
    end

    def distance_to(center, x, y)
      Math.sqrt((x - center[0])**2 + (y - center[1])**2)
    end
  end
end
