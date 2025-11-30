# frozen_string_literal: true

module Broadlistening
  module Steps
    class Clustering < BaseStep
      MIN_SAMPLES_FOR_UMAP = 15

      def execute
        arguments = context[:arguments]
        return context.merge(cluster_results: {}) if arguments.empty?

        embeddings = build_embeddings_matrix(arguments)
        umap_coords = perform_umap(embeddings)
        cluster_results = perform_hierarchical_clustering(umap_coords)

        assign_cluster_info_to_arguments(arguments, umap_coords, cluster_results)

        context.merge(
          arguments: arguments,
          cluster_results: cluster_results,
          umap_coords: umap_coords
        )
      end

      private

      def build_embeddings_matrix(arguments)
        Numo::DFloat.cast(arguments.map { |a| a[:embedding] })
      end

      def perform_umap(embeddings)
        n_samples = embeddings.shape[0]

        if n_samples < MIN_SAMPLES_FOR_UMAP || !umap_available?
          return simple_projection(embeddings)
        end

        n_neighbors = [15, n_samples - 1].min
        umap = Umappp::Umap.new(
          n_neighbors: n_neighbors,
          n_components: 2,
          random_state: 42
        )
        umap.fit_transform(embeddings)
      end

      def umap_available?
        defined?(Umappp::Umap)
      end

      def simple_projection(embeddings)
        # PCA using SVD via numo-linalg
        # This is a fallback when UMAP is not available
        n_samples = embeddings.shape[0]

        return Numo::DFloat.zeros(n_samples, 2) if n_samples == 0

        # Center the data
        mean = embeddings.mean(axis: 0)
        centered = embeddings - mean

        # Perform SVD for PCA
        # For PCA, we need the right singular vectors (V) corresponding to largest singular values
        u, s, vt = Numo::Linalg.svd(centered, full_matrices: false)

        # Project onto first 2 principal components
        # The projection is X_centered @ V[:, :2] = U[:, :2] @ S[:2]
        n_components = [2, s.size].min
        result = Numo::DFloat.zeros(n_samples, 2)

        n_components.times do |i|
          result[true, i] = u[true, i] * s[i]
        end

        result
      end

      def perform_hierarchical_clustering(umap_coords)
        cluster_nums = config.cluster_nums.sort
        n_samples = umap_coords.shape[0]

        # Adjust cluster numbers if we have fewer samples
        adjusted_cluster_nums = cluster_nums.map { |n| [n, n_samples].min }.uniq

        max_clusters = adjusted_cluster_nums.last

        # Perform KMeans with max clusters
        kmeans = Services::KMeans.new(
          n_clusters: max_clusters,
          random_state: 42
        )
        kmeans.fit(umap_coords)

        # Build hierarchical results
        build_hierarchical_results(kmeans, adjusted_cluster_nums)
      end

      def build_hierarchical_results(kmeans, cluster_nums)
        results = {}

        cluster_nums[0..-2].each_with_index do |n_target, level|
          merged_labels = Services::HierarchicalClustering.merge(
            kmeans.centroids,
            kmeans.labels,
            n_target
          )
          results[level + 1] = merged_labels
        end

        # Final level uses KMeans labels directly
        results[cluster_nums.size] = kmeans.labels

        results
      end

      def assign_cluster_info_to_arguments(arguments, umap_coords, cluster_results)
        arguments.each_with_index do |arg, idx|
          arg[:x] = umap_coords[idx, 0]
          arg[:y] = umap_coords[idx, 1]
          arg[:cluster_ids] = build_cluster_ids(idx, cluster_results)
        end
      end

      def build_cluster_ids(idx, cluster_results)
        cluster_ids = ["0"] # Root cluster

        cluster_results.keys.sort.each do |level|
          cluster_id = "#{level}_#{cluster_results[level][idx]}"
          cluster_ids << cluster_id
        end

        cluster_ids
      end
    end
  end
end
