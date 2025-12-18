# frozen_string_literal: true

module Broadlistening
  # Calculates cluster density based on point distribution.
  #
  # Density is calculated as 1 / (avg_distance_from_center + epsilon)
  # where avg_distance_from_center is the mean Euclidean distance from each point
  # in the cluster to the cluster's centroid.
  #
  # @example
  #   calculator = DensityCalculator.new(arguments, labels)
  #   densities = calculator.calculate
  #   densities["1_0"]  # => {density: 0.5, density_rank: 1, density_rank_percentile: 0.5}
  class DensityCalculator
    EPSILON = 1e-10

    # Calculate densities from pre-built cluster data (used by Aggregation step)
    #
    # @param cluster_data [Hash{String => Hash}] cluster_id => {points: [[x, y], ...], level: Integer}
    # @return [Hash{String => DensityInfo}] cluster_id => DensityInfo
    def self.calculate_with_ranks(cluster_data)
      return {} if cluster_data.empty?

      # Group by level
      by_level = cluster_data.group_by { |_, data| data[:level] }
      result = {}

      by_level.each do |_level, clusters|
        # Calculate density for each cluster
        densities = clusters.map do |cluster_id, data|
          density = calculate_single_density(data[:points])
          [ cluster_id, density ]
        end.to_h

        # Calculate ranks within this level
        sorted_ids = densities.sort_by { |_, d| -d }.map(&:first)
        sorted_ids.each_with_index do |cluster_id, idx|
          rank = idx + 1
          result[cluster_id] = DensityInfo.new(
            density: densities[cluster_id],
            density_rank: rank,
            density_rank_percentile: rank.to_f / sorted_ids.size
          )
        end
      end

      result
    end

    # Calculate density for a single cluster's points
    # @param points [Array<Array<Float>>] Array of [x, y] coordinate pairs
    # @return [Float] Density value
    def self.calculate(points)
      calculate_single_density(points)
    end

    # Calculate density for a single cluster's points (internal use)
    def self.calculate_single_density(points)
      # Handle Numo::NArray input
      points = points.to_a if points.respond_to?(:to_a) && !points.is_a?(Array)

      # Empty or single point returns maximum density
      return 1.0 / EPSILON if points.empty? || points.size == 1

      center = [
        points.sum { |p| p[0] } / points.size.to_f,
        points.sum { |p| p[1] } / points.size.to_f
      ]

      avg_distance = points.sum do |x, y|
        Math.sqrt((x - center[0])**2 + (y - center[1])**2)
      end / points.size.to_f

      1.0 / (avg_distance + EPSILON)
    end

    # @param arguments [Array<Argument>] Arguments with cluster assignments
    # @param labels [Hash{String => ClusterLabel}] Cluster labels keyed by cluster_id
    def initialize(arguments, labels)
      @arguments = arguments
      @labels = labels
    end

    # Calculate density for all clusters
    #
    # @return [Hash{String => Hash}] cluster_id => {density:, density_rank:, density_rank_percentile:}
    def calculate
      return {} if @labels.empty?

      labels_by_level = @labels.values.group_by(&:level)
      result = {}

      labels_by_level.each do |level, level_labels|
        densities = calculate_densities_for_level(level_labels, level)
        ranks = calculate_ranks(densities)

        level_labels.each do |label|
          cluster_id = label.cluster_id
          rank = ranks[cluster_id]

          result[cluster_id] = {
            density: densities[cluster_id],
            density_rank: rank,
            density_rank_percentile: rank.to_f / level_labels.size
          }
        end
      end

      result
    end

    private

    def calculate_densities_for_level(level_labels, level)
      level_labels.to_h do |label|
        [ label.cluster_id, calculate_single_density(label.cluster_id, level) ]
      end
    end

    def calculate_ranks(densities)
      sorted_ids = densities.sort_by { |_, d| -d }.map(&:first)
      sorted_ids.each_with_index.to_h { |id, idx| [ id, idx + 1 ] }
    end

    def calculate_single_density(cluster_id, level)
      coords = cluster_coordinates(cluster_id, level)
      return 0.0 if coords.empty?

      center = calculate_centroid(coords)
      avg_distance = calculate_avg_distance(coords, center)

      1.0 / (avg_distance + EPSILON)
    end

    def cluster_coordinates(cluster_id, level)
      @arguments.filter_map do |arg|
        next unless arg.cluster_ids && arg.cluster_ids[level] == cluster_id
        next unless arg.x && arg.y

        [ arg.x, arg.y ]
      end
    end

    def calculate_centroid(coords)
      [
        coords.sum { |c| c[0] } / coords.size.to_f,
        coords.sum { |c| c[1] } / coords.size.to_f
      ]
    end

    def calculate_avg_distance(coords, center)
      distances = coords.map do |x, y|
        Math.sqrt((x - center[0])**2 + (y - center[1])**2)
      end
      distances.sum / distances.size.to_f
    end
  end
end
