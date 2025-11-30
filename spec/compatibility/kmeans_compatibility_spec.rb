# frozen_string_literal: true

require "spec_helper"

RSpec.describe "KMeans Numerical Compatibility" do
  let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }

  let(:reference_data) do
    JSON.parse(File.read(File.join(fixtures_dir, "clustering_reference.json")))
  end

  let(:kmeans_reference) { reference_data["kmeans"] }

  describe "KMeans vs sklearn" do
    let(:data) { kmeans_reference["data"] }
    let(:n_clusters) { kmeans_reference["n_clusters"] }
    let(:sklearn_labels) { kmeans_reference["labels"] }
    let(:sklearn_centroids) { kmeans_reference["centroids"] }
    let(:sklearn_inertia) { kmeans_reference["inertia"] }

    let(:ruby_kmeans) do
      kmeans = Broadlistening::KMeans.new(n_clusters: n_clusters, random_state: 42)
      kmeans.fit(data)
      kmeans
    end

    describe "cluster assignment consistency" do
      it "produces same number of unique labels" do
        expect(ruby_kmeans.labels.uniq.size).to eq(sklearn_labels.uniq.size)
      end

      it "assigns points to clusters consistently" do
        # KMeans can produce different label numbering but same groupings
        # Check that points grouped together in sklearn are also grouped in Ruby

        sklearn_groups = sklearn_labels.each_with_index.group_by { |label, _| label }
        ruby_groups = ruby_kmeans.labels.each_with_index.group_by { |label, _| label }

        sklearn_point_sets = sklearn_groups.values.map { |pairs| pairs.map(&:last).sort }
        ruby_point_sets = ruby_groups.values.map { |pairs| pairs.map(&:last).sort }

        # Sort both for comparison (order of clusters doesn't matter)
        expect(ruby_point_sets.sort).to eq(sklearn_point_sets.sort)
      end
    end

    describe "centroid computation" do
      it "produces centroids nearly identical to sklearn centroids" do
        ruby_centroids = ruby_kmeans.centroids.to_a

        # Match centroids by finding closest pairs
        matched = match_centroids(ruby_centroids, sklearn_centroids)

        matched.each do |ruby_c, sklearn_c, distance|
          # With same random_state, centroids should be essentially identical
          # (floating point precision level difference only)
          expect(distance).to be < 1e-10,
            "Centroid distance #{distance} exceeds tolerance. Ruby: #{ruby_c}, sklearn: #{sklearn_c}"
        end
      end
    end

    describe "inertia computation" do
      it "produces identical inertia to sklearn" do
        # With same random_state and same cluster assignments, inertia should be identical
        # (floating point precision level difference only)
        expect(ruby_kmeans.inertia).to be_within(1e-10).of(sklearn_inertia)
      end
    end

    describe "deterministic behavior" do
      it "produces same results with same random_state" do
        kmeans1 = Broadlistening::KMeans.new(n_clusters: n_clusters, random_state: 42)
        kmeans2 = Broadlistening::KMeans.new(n_clusters: n_clusters, random_state: 42)

        kmeans1.fit(data)
        kmeans2.fit(data)

        expect(kmeans1.labels).to eq(kmeans2.labels)
        expect(kmeans1.centroids.to_a).to eq(kmeans2.centroids.to_a)
      end

      it "produces different results with different random_state" do
        kmeans1 = Broadlistening::KMeans.new(n_clusters: n_clusters, random_state: 42)
        kmeans2 = Broadlistening::KMeans.new(n_clusters: n_clusters, random_state: 123)

        kmeans1.fit(data)
        kmeans2.fit(data)

        # Labels might be same if clusters are well-separated, but centroids init differs
        # At minimum, the initial centroid selection should be different
        expect(kmeans1.centroids.to_a).not_to eq(kmeans2.centroids.to_a)
      end
    end
  end

  describe "Adjusted Rand Index" do
    # Adjusted Rand Index measures clustering similarity (1.0 = perfect match)

    let(:data) { kmeans_reference["data"] }
    let(:sklearn_labels) { kmeans_reference["labels"] }

    it "achieves high ARI score vs sklearn" do
      kmeans = Broadlistening::KMeans.new(n_clusters: 3, random_state: 42)
      kmeans.fit(data)

      ari = adjusted_rand_index(sklearn_labels, kmeans.labels)

      # ARI should be very high for well-separated clusters
      expect(ari).to be > 0.95,
        "ARI score #{ari} indicates clustering mismatch with sklearn"
    end
  end

  private

  def match_centroids(ruby_centroids, sklearn_centroids)
    # Match each Ruby centroid to closest sklearn centroid
    matches = []
    used_sklearn = []

    ruby_centroids.each do |ruby_c|
      best_match = nil
      best_distance = Float::INFINITY

      sklearn_centroids.each_with_index do |sklearn_c, idx|
        next if used_sklearn.include?(idx)

        distance = euclidean_distance(ruby_c, sklearn_c)
        if distance < best_distance
          best_distance = distance
          best_match = idx
        end
      end

      used_sklearn << best_match
      matches << [ ruby_c, sklearn_centroids[best_match], best_distance ]
    end

    matches
  end

  def euclidean_distance(a, b)
    Math.sqrt(a.zip(b).map { |x, y| (x - y) ** 2 }.sum)
  end

  def adjusted_rand_index(labels_true, labels_pred)
    # Compute Adjusted Rand Index
    n = labels_true.size
    return 1.0 if n == 0

    # Build contingency table
    contingency = Hash.new { |h, k| h[k] = Hash.new(0) }
    labels_true.zip(labels_pred).each do |t, p|
      contingency[t][p] += 1
    end

    # Sum of combinations
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
