# frozen_string_literal: true

module Broadlistening
  module Steps
    class Clustering < BaseStep
      def execute
        return context if context.arguments.empty?

        embeddings = build_embeddings_matrix(context.arguments)
        umap_coords = perform_umap(embeddings)
        cluster_results = perform_hierarchical_clustering(umap_coords)

        assign_cluster_info_to_arguments(context.arguments, umap_coords, cluster_results)

        context.cluster_results = cluster_results
        context.umap_coords = umap_coords
        context
      end

      private

      def build_embeddings_matrix(arguments)
        Numo::DFloat.cast(arguments.map(&:embedding))
      end

      def perform_umap(embeddings)
        n_samples = embeddings.shape[0]
        default_n_neighbors = 15

        # For small datasets, reduce n_neighbors to avoid UMAP errors
        # Python: n_neighbors = max(2, n_samples - 1) when n_samples <= 15
        num_neighbors = n_samples <= default_n_neighbors ? [ 2, n_samples - 1 ].max : default_n_neighbors

        # Convert to SFloat for umappp (required format)
        embeddings_sfloat = Numo::SFloat.cast(embeddings)

        # Umappp.run returns 2D coordinates
        result = Umappp.run(
          embeddings_sfloat,
          ndim: 2,
          num_neighbors: num_neighbors,
          seed: 42
        )

        # Convert back to DFloat for consistency
        Numo::DFloat.cast(result)
      end

      def perform_hierarchical_clustering(umap_coords)
        cluster_nums = config.cluster_nums.sort
        n_samples = umap_coords.shape[0]

        # Adjust cluster numbers if we have fewer samples
        adjusted_cluster_nums = cluster_nums.map { |n| [ n, n_samples ].min }.uniq

        max_clusters = adjusted_cluster_nums.last

        # Perform KMeans with max clusters
        kmeans = KMeans.new(
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
          merged_labels = HierarchicalClustering.merge(
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
          arg.x = umap_coords[idx, 0]
          arg.y = umap_coords[idx, 1]
          arg.cluster_ids = build_cluster_ids(idx, cluster_results)
        end
      end

      def build_cluster_ids(idx, cluster_results)
        cluster_ids = [ "0" ] # Root cluster

        cluster_results.keys.sort.each do |level|
          cluster_id = "#{level}_#{cluster_results[level][idx]}"
          cluster_ids << cluster_id
        end

        cluster_ids
      end
    end
  end
end
