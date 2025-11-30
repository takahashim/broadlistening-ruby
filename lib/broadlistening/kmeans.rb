# frozen_string_literal: true

module Broadlistening
  class KMeans
    attr_reader :centroids, :labels, :n_clusters, :inertia

    DEFAULT_MAX_ITERATIONS = 100
    DEFAULT_TOLERANCE = 1e-6

    def initialize(n_clusters:, max_iterations: DEFAULT_MAX_ITERATIONS, random_state: nil, tolerance: DEFAULT_TOLERANCE)
      @n_clusters = n_clusters
      @max_iterations = max_iterations
      @tolerance = tolerance
      @random = random_state ? Random.new(random_state) : Random.new
      @centroids = nil
      @labels = nil
      @inertia = nil
    end

    def fit(data)
      @data = to_numo_array(data)
      validate_data!

      @centroids = initialize_centroids_pp
      @labels = Array.new(@data.shape[0])

      @max_iterations.times do
        @labels = assign_labels
        new_centroids = update_centroids

        if converged?(new_centroids)
          @centroids = new_centroids
          break
        end

        @centroids = new_centroids
      end

      @inertia = compute_inertia
      self
    end

    def predict(data)
      data = to_numo_array(data)
      assign_labels_for(data)
    end

    def fit_predict(data)
      fit(data)
      @labels
    end

    private

    def to_numo_array(data)
      return data if data.is_a?(Numo::DFloat)

      Numo::DFloat.cast(data)
    end

    def validate_data!
      n_samples = @data.shape[0]
      raise ClusteringError, "n_clusters (#{@n_clusters}) must be <= n_samples (#{n_samples})" if @n_clusters > n_samples
      raise ClusteringError, "n_clusters must be positive" if @n_clusters <= 0
    end

    def initialize_centroids_pp
      n_samples = @data.shape[0]
      n_features = @data.shape[1]
      centroids = Numo::DFloat.zeros(@n_clusters, n_features)

      first_idx = @random.rand(n_samples)
      centroids[0, true] = @data[first_idx, true]

      (1...@n_clusters).each do |k|
        distances = compute_min_distances_to_centroids(centroids[0...k, true])
        probabilities = distances**2
        sum_probs = probabilities.sum
        probabilities /= sum_probs if sum_probs > 0

        next_idx = weighted_random_choice(probabilities)
        centroids[k, true] = @data[next_idx, true]
      end

      centroids
    end

    def compute_min_distances_to_centroids(centroids)
      n_samples = @data.shape[0]
      min_distances = Numo::DFloat.new(n_samples).fill(Float::INFINITY)

      centroids.shape[0].times do |k|
        distances = compute_distances_to_centroid(@data, centroids[k, true])
        min_distances = Numo::DFloat.minimum(min_distances, distances)
      end

      min_distances
    end

    def compute_distances_to_centroid(points, centroid)
      diff = points - centroid
      (diff**2).sum(axis: 1)
    end

    def weighted_random_choice(probabilities)
      cumsum = 0.0
      threshold = @random.rand
      probs_array = probabilities.to_a

      probs_array.each_with_index do |prob, idx|
        cumsum += prob
        return idx if cumsum >= threshold
      end

      probs_array.size - 1
    end

    def assign_labels
      assign_labels_for(@data)
    end

    def assign_labels_for(data)
      n_samples = data.shape[0]
      labels = Array.new(n_samples)

      n_samples.times do |i|
        point = data[i, true]
        min_dist = Float::INFINITY
        min_label = 0

        @n_clusters.times do |k|
          dist = squared_distance(point, @centroids[k, true])
          if dist < min_dist
            min_dist = dist
            min_label = k
          end
        end

        labels[i] = min_label
      end

      labels
    end

    def squared_distance(a, b)
      ((a - b)**2).sum
    end

    def update_centroids
      n_features = @data.shape[1]
      new_centroids = Numo::DFloat.zeros(@n_clusters, n_features)
      counts = Array.new(@n_clusters, 0)

      @data.shape[0].times do |i|
        label = @labels[i]
        new_centroids[label, true] += @data[i, true]
        counts[label] += 1
      end

      @n_clusters.times do |k|
        if counts[k] > 0
          new_centroids[k, true] /= counts[k]
        else
          random_idx = @random.rand(@data.shape[0])
          new_centroids[k, true] = @data[random_idx, true]
        end
      end

      new_centroids
    end

    def converged?(new_centroids)
      ((@centroids - new_centroids)**2).sum < @tolerance
    end

    def compute_inertia
      total = 0.0
      @data.shape[0].times do |i|
        label = @labels[i]
        total += squared_distance(@data[i, true], @centroids[label, true])
      end
      total
    end
  end
end
