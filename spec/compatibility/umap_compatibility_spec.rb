# frozen_string_literal: true

require "spec_helper"

RSpec.describe "UMAP Structural Compatibility" do
  # UMAP implementations (Python umap-learn vs Ruby umappp) may produce
  # different absolute coordinates, but should preserve the structural
  # relationships in the data. These tests verify that:
  # 1. Points that are close in embedding space remain close in UMAP space
  # 2. The overall distribution has similar characteristics
  # 3. Clustering results are similar despite coordinate differences

  let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }

  let(:python_embeddings) do
    JSON.parse(File.read(File.join(fixtures_dir, "embeddings.json")))
  end

  let(:python_result) do
    JSON.parse(File.read(File.join(fixtures_dir, "hierarchical_result.json")))
  end

  let(:python_coordinates) do
    python_result["arguments"].map { |a| [ a["x"], a["y"] ] }
  end

  let(:embeddings_matrix) do
    vectors = python_embeddings.map { |e| e["embedding"] }
    Numo::DFloat.cast(vectors)
  end

  describe "UMAP coordinate distribution" do
    let(:ruby_coordinates) do
      n_samples = embeddings_matrix.shape[0]
      num_neighbors = [ 15, n_samples - 1 ].min

      embeddings_sfloat = Numo::SFloat.cast(embeddings_matrix)
      result = Umappp.run(
        embeddings_sfloat,
        ndim: 2,
        num_neighbors: num_neighbors,
        seed: 42
      )

      Numo::DFloat.cast(result).to_a
    end

    it "produces coordinates in similar range as Python" do
      ruby_x_range = ruby_coordinates.map(&:first).minmax
      ruby_y_range = ruby_coordinates.map(&:last).minmax

      python_x_range = python_coordinates.map(&:first).minmax
      python_y_range = python_coordinates.map(&:last).minmax

      # Ranges should be within same order of magnitude
      ruby_x_span = ruby_x_range[1] - ruby_x_range[0]
      ruby_y_span = ruby_y_range[1] - ruby_y_range[0]
      python_x_span = python_x_range[1] - python_x_range[0]
      python_y_span = python_y_range[1] - python_y_range[0]

      expect(ruby_x_span).to be_within(python_x_span * 2).of(python_x_span)
      expect(ruby_y_span).to be_within(python_y_span * 2).of(python_y_span)
    end

    it "produces non-degenerate distribution" do
      x_values = ruby_coordinates.map(&:first)
      y_values = ruby_coordinates.map(&:last)

      x_variance = variance(x_values)
      y_variance = variance(y_values)

      # Should have meaningful spread, not all points at same location
      expect(x_variance).to be > 0.1
      expect(y_variance).to be > 0.1
    end
  end

  describe "Pairwise distance preservation" do
    # UMAP should approximately preserve local neighborhood structure
    # Points that are close in high-dimensional space should be
    # relatively close in 2D space

    let(:sample_size) { 50 } # Use subset for performance

    let(:sample_indices) do
      # Deterministic sample
      (0...embeddings_matrix.shape[0]).to_a.each_slice(embeddings_matrix.shape[0] / sample_size).map(&:first).take(sample_size)
    end

    let(:sample_embeddings) do
      sample_indices.map { |i| embeddings_matrix[i, true].to_a }
    end

    let(:ruby_sample_coords) do
      sample_embeddings_matrix = Numo::SFloat.cast(sample_embeddings)
      num_neighbors = [ 15, sample_size - 1 ].min

      result = Umappp.run(
        sample_embeddings_matrix,
        ndim: 2,
        num_neighbors: num_neighbors,
        seed: 42
      )

      Numo::DFloat.cast(result).to_a
    end

    let(:python_sample_coords) do
      sample_indices.map { |i| python_coordinates[i] }
    end

    it "preserves nearest neighbor relationships" do
      # For each point, check if its nearest neighbors in embedding space
      # are among its nearest neighbors in UMAP space

      preserved_count = 0
      k = 5 # Check top-5 neighbors

      sample_size.times do |i|
        # Find k nearest neighbors in original space
        original_distances = sample_size.times.map do |j|
          next Float::INFINITY if i == j
          euclidean_distance(sample_embeddings[i], sample_embeddings[j])
        end
        original_neighbors = original_distances.each_with_index.sort.take(k).map(&:last)

        # Find k nearest neighbors in UMAP space
        umap_distances = sample_size.times.map do |j|
          next Float::INFINITY if i == j
          euclidean_distance(ruby_sample_coords[i], ruby_sample_coords[j])
        end
        umap_neighbors = umap_distances.each_with_index.sort.take(k).map(&:last)

        # Count overlap
        overlap = (original_neighbors & umap_neighbors).size
        preserved_count += overlap
      end

      preservation_rate = preserved_count.to_f / (sample_size * k)

      # Expect at least 30% of nearest neighbors to be preserved
      # (UMAP focuses on local structure but isn't perfect)
      expect(preservation_rate).to be > 0.3,
        "Neighbor preservation rate #{preservation_rate} is too low"
    end
  end

  describe "Clustering consistency" do
    # Even if UMAP coordinates differ, clustering results should be similar

    let(:cluster_nums) { [ 5, 15 ] }

    let(:ruby_cluster_result) do
      n_samples = embeddings_matrix.shape[0]
      num_neighbors = [ 15, n_samples - 1 ].min

      embeddings_sfloat = Numo::SFloat.cast(embeddings_matrix)
      umap_result = Umappp.run(
        embeddings_sfloat,
        ndim: 2,
        num_neighbors: num_neighbors,
        seed: 42
      )
      umap_coords = Numo::DFloat.cast(umap_result)

      # Run KMeans
      max_clusters = cluster_nums.max
      kmeans = Broadlistening::KMeans.new(n_clusters: max_clusters, random_state: 42)
      kmeans.fit(umap_coords)

      kmeans.labels
    end

    let(:python_cluster_result) do
      # Extract cluster assignments from Python result (level 2 = max clusters)
      python_result["arguments"].map do |arg|
        # cluster_ids format: ["0", "1_X", "2_Y"] - extract level 2
        level_2_id = arg["cluster_ids"].find { |id| id.start_with?("2_") }
        level_2_id&.split("_")&.last&.to_i || 0
      end
    end

    it "produces similar cluster count at max level" do
      ruby_cluster_count = ruby_cluster_result.uniq.size
      python_cluster_count = python_cluster_result.uniq.size

      # Should be within same range
      expect(ruby_cluster_count).to be_within(5).of(python_cluster_count)
    end

    it "achieves reasonable Adjusted Rand Index vs Python" do
      ari = adjusted_rand_index(python_cluster_result, ruby_cluster_result)

      # Note: Different UMAP implementations (umap-learn vs umappp) produce
      # different embeddings, which leads to different cluster boundaries.
      # ARI > 0.1 indicates some meaningful agreement despite implementation differences.
      # For perfect compatibility, embeddings would need to be pre-computed and shared.
      expect(ari).to be > 0.1,
        "ARI #{ari} indicates poor clustering agreement with Python"
    end
  end

  describe "Deterministic behavior" do
    it "produces same coordinates with same seed" do
      n_samples = [ embeddings_matrix.shape[0], 100 ].min
      small_embeddings = Numo::SFloat.cast(embeddings_matrix[0...n_samples, true])
      num_neighbors = [ 15, n_samples - 1 ].min

      result1 = Umappp.run(small_embeddings, ndim: 2, num_neighbors: num_neighbors, seed: 42)
      result2 = Umappp.run(small_embeddings, ndim: 2, num_neighbors: num_neighbors, seed: 42)

      expect(result1.to_a).to eq(result2.to_a)
    end
  end

  private

  def euclidean_distance(a, b)
    Math.sqrt(a.zip(b).map { |x, y| (x - y) ** 2 }.sum)
  end

  def variance(values)
    mean = values.sum / values.size.to_f
    values.map { |v| (v - mean) ** 2 }.sum / values.size
  end

  def adjusted_rand_index(labels_true, labels_pred)
    n = labels_true.size
    return 1.0 if n == 0

    contingency = Hash.new { |h, k| h[k] = Hash.new(0) }
    labels_true.zip(labels_pred).each do |t, p|
      contingency[t][p] += 1
    end

    sum_comb_c = 0
    contingency.each_value do |row|
      row.each_value { |nij| sum_comb_c += comb2(nij) }
    end

    sum_comb_k = labels_true.tally.values.sum { |n| comb2(n) }
    sum_comb_j = labels_pred.tally.values.sum { |n| comb2(n) }

    total_comb = comb2(n)
    return 1.0 if total_comb == 0

    expected = (sum_comb_k * sum_comb_j).to_f / total_comb
    max_index = (sum_comb_k + sum_comb_j) / 2.0
    denominator = max_index - expected

    return 1.0 if denominator == 0

    (sum_comb_c - expected) / denominator
  end

  def comb2(n)
    n >= 2 ? n * (n - 1) / 2 : 0
  end
end
