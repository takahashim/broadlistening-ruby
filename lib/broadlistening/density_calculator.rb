# frozen_string_literal: true

module Broadlistening
  # Calculates cluster density based on average distance from centroid
  # Compatible with Python's calculate_density function in hierarchical_merge_labelling.py
  class DensityCalculator
    EPSILON = 1e-10

    class << self
      # Calculate density for a single cluster
      # @param points [Array<Array<Float>>, Numo::DFloat] 2D coordinates of points in the cluster
      # @return [Float] density value (1 / average_distance_to_center)
      def calculate(points)
        points_array = to_numo_array(points)
        return EPSILON**-1 if points_array.shape[0] == 0

        center = calculate_center(points_array)
        distances = calculate_distances(points_array, center)
        avg_distance = distances.mean

        1.0 / (avg_distance + EPSILON)
      end

      # Calculate density for multiple clusters and compute rank percentiles
      # @param clusters [Hash] cluster_id => { points: [[x, y], ...], level: Integer }
      # @return [Hash] cluster_id => { density: Float, density_rank: Integer, density_rank_percentile: Float }
      def calculate_with_ranks(clusters)
        # Calculate density for each cluster
        densities = clusters.transform_values do |cluster_data|
          {
            density: calculate(cluster_data[:points]),
            level: cluster_data[:level]
          }
        end

        # Group by level and calculate ranks within each level
        by_level = densities.group_by { |_id, data| data[:level] }

        result = {}
        by_level.each do |_level, level_clusters|
          # Sort by density descending and assign ranks
          sorted = level_clusters.sort_by { |_id, data| -data[:density] }
          level_size = sorted.size

          sorted.each_with_index do |(cluster_id, data), index|
            rank = index + 1
            result[cluster_id] = {
              density: data[:density],
              density_rank: rank,
              density_rank_percentile: rank.to_f / level_size
            }
          end
        end

        result
      end

      private

      def to_numo_array(points)
        case points
        when Numo::DFloat
          points
        when Numo::NArray
          Numo::DFloat.cast(points)
        when Array
          return Numo::DFloat.zeros(0, 2) if points.empty?

          Numo::DFloat.cast(points)
        else
          raise ArgumentError, "points must be an Array or Numo::NArray, got #{points.class}"
        end
      end

      def calculate_center(points)
        # Mean along axis 0 (column-wise mean)
        points.mean(axis: 0)
      end

      def calculate_distances(points, center)
        # Calculate Euclidean distance from each point to center
        # np.linalg.norm(points - center, axis=1)
        diff = points - center
        Numo::DFloat::Math.sqrt((diff**2).sum(axis: 1))
      end
    end
  end
end
