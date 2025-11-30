# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Hierarchical Merge Numerical Compatibility" do
  let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }

  let(:reference_data) do
    JSON.parse(File.read(File.join(fixtures_dir, "clustering_reference.json")))
  end

  let(:hierarchical_reference) { reference_data["hierarchical"] }
  let(:ward_linkage_reference) { reference_data["ward_linkage"] }

  describe "HierarchicalClustering.merge vs scipy" do
    let(:centroids) { hierarchical_reference["centroids"] }
    let(:original_labels) { hierarchical_reference["original_labels"] }
    let(:scipy_results) { hierarchical_reference["results"] }

    describe "merging to 3 clusters" do
      let(:scipy_labels) { scipy_results["n_clusters_3"]["merged_labels"] }

      it "produces same cluster groupings as scipy" do
        ruby_labels = Broadlistening::HierarchicalClustering.merge(
          centroids,
          original_labels,
          3
        )

        expect(groupings_equivalent?(ruby_labels, scipy_labels)).to eq(true),
          -> { "Ruby labels #{ruby_labels} do not match scipy labels #{scipy_labels}" }
      end

      it "produces correct number of clusters" do
        ruby_labels = Broadlistening::HierarchicalClustering.merge(
          centroids,
          original_labels,
          3
        )

        expect(ruby_labels.uniq.size).to eq(3)
      end

      it "preserves points within original clusters" do
        ruby_labels = Broadlistening::HierarchicalClustering.merge(
          centroids,
          original_labels,
          3
        )

        # Points 0,1 should be together (both originally in cluster 0)
        expect(ruby_labels[0]).to eq(ruby_labels[1])
        # Points 2,3 should be together (both originally in cluster 1)
        expect(ruby_labels[2]).to eq(ruby_labels[3])
      end
    end

    describe "merging to 2 clusters" do
      let(:scipy_labels) { scipy_results["n_clusters_2"]["merged_labels"] }

      it "produces same cluster groupings as scipy" do
        ruby_labels = Broadlistening::HierarchicalClustering.merge(
          centroids,
          original_labels,
          2
        )

        expect(groupings_equivalent?(ruby_labels, scipy_labels)).to eq(true),
          -> { "Ruby labels #{ruby_labels} do not match scipy labels #{scipy_labels}" }
      end
    end

    describe "merging to 1 cluster" do
      it "produces all same labels" do
        ruby_labels = Broadlistening::HierarchicalClustering.merge(
          centroids,
          original_labels,
          1
        )

        expect(ruby_labels.uniq.size).to eq(1)
      end
    end
  end

  describe "Ward linkage test cases" do
    it "produces equivalent 2-cluster result for 4_points_unequal" do
      test_case = ward_linkage_reference.find { |tc| tc["name"] == "4_points_unequal" }
      points = test_case["points"]
      scipy_fcluster_2 = test_case["fcluster_2"]

      original_labels = (0...points.size).to_a
      ruby_labels = Broadlistening::HierarchicalClustering.merge(points, original_labels, 2)

      expect(groupings_equivalent?(ruby_labels, scipy_fcluster_2)).to eq(true),
        -> { "2-cluster mismatch: Ruby #{ruby_labels} vs scipy #{scipy_fcluster_2}" }
    end

    it "produces equivalent 3-cluster result for 4_points_unequal" do
      test_case = ward_linkage_reference.find { |tc| tc["name"] == "4_points_unequal" }
      points = test_case["points"]
      scipy_fcluster_3 = test_case["fcluster_3"]

      original_labels = (0...points.size).to_a
      ruby_labels = Broadlistening::HierarchicalClustering.merge(points, original_labels, 3)

      # Points: [0,0], [1,0], [5,0], [7,0]
      # With unequal distances (1.0 vs 2.0), scipy fcluster correctly returns 3 clusters
      # scipy fcluster_3 = [1, 1, 2, 3]
      expect(groupings_equivalent?(ruby_labels, scipy_fcluster_3)).to eq(true),
        -> { "3-cluster mismatch: Ruby #{ruby_labels} vs scipy #{scipy_fcluster_3}" }
    end

    it "produces equivalent 2-cluster result for 6_points_2d" do
      test_case = ward_linkage_reference.find { |tc| tc["name"] == "6_points_2d" }
      points = test_case["points"]
      scipy_fcluster_2 = test_case["fcluster_2"]

      original_labels = (0...points.size).to_a
      ruby_labels = Broadlistening::HierarchicalClustering.merge(points, original_labels, 2)

      expect(groupings_equivalent?(ruby_labels, scipy_fcluster_2)).to eq(true),
        -> { "2-cluster mismatch: Ruby #{ruby_labels} vs scipy #{scipy_fcluster_2}" }
    end

    it "produces equivalent 3-cluster result for 6_points_2d" do
      test_case = ward_linkage_reference.find { |tc| tc["name"] == "6_points_2d" }
      points = test_case["points"]
      scipy_fcluster_3 = test_case["fcluster_3"]

      original_labels = (0...points.size).to_a
      ruby_labels = Broadlistening::HierarchicalClustering.merge(points, original_labels, 3)

      expect(groupings_equivalent?(ruby_labels, scipy_fcluster_3)).to eq(true),
        -> { "3-cluster mismatch: Ruby #{ruby_labels} vs scipy #{scipy_fcluster_3}" }
    end
  end

  describe "Merge behavior with Numo::DFloat input" do
    let(:centroids) do
      Numo::DFloat[
        [ 0.0, 0.0 ],
        [ 1.0, 0.0 ],
        [ 10.0, 0.0 ],
        [ 11.0, 0.0 ]
      ]
    end

    let(:labels) { [ 0, 0, 1, 1, 2, 2, 3, 3 ] }

    it "accepts Numo::DFloat input" do
      result = Broadlistening::HierarchicalClustering.merge(centroids, labels, 2)

      expect(result).to be_an(Array)
      expect(result.size).to eq(labels.size)
      expect(result.uniq.size).to eq(2)
    end

    it "merges nearby clusters correctly" do
      result = Broadlistening::HierarchicalClustering.merge(centroids, labels, 2)

      # Clusters 0,1 (centroids at 0,1) should merge
      expect(result[0]).to eq(result[2])
      # Clusters 2,3 (centroids at 10,11) should merge
      expect(result[4]).to eq(result[6])
      # The two merged groups should be different
      expect(result[0]).not_to eq(result[4])
    end
  end

  describe "Label remapping" do
    it "produces contiguous labels starting from 0" do
      centroids = [ [ 0, 0 ], [ 5, 0 ], [ 10, 0 ], [ 15, 0 ] ]
      labels = [ 0, 1, 2, 3 ]

      result = Broadlistening::HierarchicalClustering.merge(centroids, labels, 2)

      expect(result.min).to eq(0)
      expect(result.max).to be <= 1
      expect(result.uniq.sort).to eq([ 0, 1 ])
    end
  end

  describe "Deterministic behavior" do
    it "produces same results on multiple runs" do
      centroids = hierarchical_reference["centroids"]
      original_labels = hierarchical_reference["original_labels"]

      result1 = Broadlistening::HierarchicalClustering.merge(centroids, original_labels, 3)
      result2 = Broadlistening::HierarchicalClustering.merge(centroids, original_labels, 3)

      expect(result1).to eq(result2)
    end
  end

  private

  def groupings_equivalent?(labels1, labels2)
    # Two labelings are equivalent if they define the same groupings
    # (even if the actual label numbers differ)
    return false unless labels1.size == labels2.size

    # Build mapping from labels1 to labels2
    mapping = {}
    labels1.zip(labels2).each do |l1, l2|
      if mapping.key?(l1)
        return false unless mapping[l1] == l2
      else
        mapping[l1] = l2
      end
    end

    # Also check reverse mapping (bijection)
    reverse_mapping = {}
    labels2.zip(labels1).each do |l2, l1|
      if reverse_mapping.key?(l2)
        return false unless reverse_mapping[l2] == l1
      else
        reverse_mapping[l2] = l1
      end
    end

    true
  end
end
