# frozen_string_literal: true

RSpec.describe Broadlistening::HierarchicalClustering do
  describe ".merge" do
    context "with simple centroids" do
      let(:centroids) do
        [
          [ 0.0, 0.0 ],   # cluster 0
          [ 1.0, 0.0 ],   # cluster 1 - close to 0
          [ 10.0, 0.0 ],  # cluster 2
          [ 11.0, 0.0 ],  # cluster 3 - close to 2
          [ 20.0, 0.0 ],  # cluster 4
          [ 21.0, 0.0 ]   # cluster 5 - close to 4
        ]
      end

      let(:labels) { [ 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 ] }

      it "merges clusters to reach target count" do
        result = described_class.merge(centroids, labels, 3)

        expect(result.uniq.size).to eq(3)
      end

      it "preserves relationships within original clusters" do
        result = described_class.merge(centroids, labels, 3)

        # Points that were in the same original cluster should still be together
        expect(result[0]).to eq(result[1])
        expect(result[2]).to eq(result[3])
        expect(result[4]).to eq(result[5])
      end

      it "merges nearby clusters together" do
        result = described_class.merge(centroids, labels, 3)

        # Cluster 0 and 1 are close, so they should be merged
        expect(result[0]).to eq(result[2])
        # Cluster 2 and 3 are close, so they should be merged
        expect(result[4]).to eq(result[6])
        # Cluster 4 and 5 are close, so they should be merged
        expect(result[8]).to eq(result[10])
      end

      it "returns original labels if already at target" do
        result = described_class.merge(centroids, [ 0, 1, 2 ], 3)

        expect(result.uniq.size).to eq(3)
      end

      it "returns original labels if below target" do
        result = described_class.merge(centroids[0..1], [ 0, 0, 1, 1 ], 5)

        expect(result.uniq.size).to eq(2)
      end
    end

    context "with Numo::DFloat centroids" do
      let(:centroids) { Numo::DFloat[[ 0.0, 0.0 ], [ 1.0, 0.0 ], [ 10.0, 0.0 ], [ 11.0, 0.0 ]] }
      let(:labels) { [ 0, 0, 1, 1, 2, 2, 3, 3 ] }

      it "accepts Numo::DFloat input" do
        result = described_class.merge(centroids, labels, 2)

        expect(result.uniq.size).to eq(2)
        expect(result[0]).to eq(result[2]) # 0 and 1 merged
        expect(result[4]).to eq(result[6]) # 2 and 3 merged
      end
    end

    context "with single cluster target" do
      let(:centroids) { [ [ 0, 0 ], [ 5, 5 ], [ 10, 10 ] ] }
      let(:labels) { [ 0, 1, 2 ] }

      it "merges all clusters into one" do
        result = described_class.merge(centroids, labels, 1)

        expect(result.uniq.size).to eq(1)
        expect(result).to eq([ 0, 0, 0 ])
      end
    end

    context "with 2D cluster arrangement" do
      let(:centroids) do
        [
          [ 0.0, 0.0 ],   # 0: bottom-left
          [ 1.0, 0.0 ],   # 1: bottom-left adjacent
          [ 0.0, 10.0 ],  # 2: top-left
          [ 1.0, 10.0 ],  # 3: top-left adjacent
          [ 10.0, 5.0 ],  # 4: right-center
          [ 11.0, 5.0 ]   # 5: right-center adjacent
        ]
      end

      let(:labels) { [ 0, 1, 2, 3, 4, 5 ] }

      it "merges spatially close clusters" do
        result = described_class.merge(centroids, labels, 3)

        expect(result.uniq.size).to eq(3)
        # 0 and 1 should be merged (distance 1.0)
        expect(result[0]).to eq(result[1])
        # 2 and 3 should be merged (distance 1.0)
        expect(result[2]).to eq(result[3])
        # 4 and 5 should be merged (distance 1.0)
        expect(result[4]).to eq(result[5])
      end
    end

    context "with average linkage" do
      let(:centroids) do
        [
          [ 0.0, 0.0 ],
          [ 2.0, 0.0 ],
          [ 4.0, 0.0 ],
          [ 100.0, 0.0 ]
        ]
      end

      it "uses average linkage distance for merging decisions" do
        labels = [ 0, 1, 2, 3 ]
        result = described_class.merge(centroids, labels, 2)

        expect(result.uniq.size).to eq(2)
        # Cluster 3 (at 100) should be separate from others
        expect(result[3]).not_to eq(result[0])
      end
    end

    context "with remapping" do
      let(:centroids) { [ [ 0, 0 ], [ 1, 0 ], [ 10, 0 ] ] }
      let(:labels) { [ 0, 1, 2 ] }

      it "produces contiguous cluster IDs starting from 0" do
        result = described_class.merge(centroids, labels, 2)

        expect(result.min).to eq(0)
        expect(result.max).to eq(1)
        expect(result.uniq.sort).to eq([ 0, 1 ])
      end
    end

    context "edge cases" do
      it "handles empty labels" do
        result = described_class.merge([ [ 0, 0 ] ], [], 1)
        expect(result).to eq([])
      end

      it "handles single point" do
        result = described_class.merge([ [ 0, 0 ] ], [ 0 ], 1)
        expect(result).to eq([ 0 ])
      end

      it "handles target equal to current cluster count" do
        centroids = [ [ 0, 0 ], [ 10, 10 ] ]
        labels = [ 0, 1 ]
        result = described_class.merge(centroids, labels, 2)

        expect(result.uniq.size).to eq(2)
      end
    end
  end

  describe "integration with KMeans" do
    it "works correctly with KMeans output" do
      # Generate clustered data
      data = []
      20.times { |i| data << [ i * 0.1, 0.0 ] }
      20.times { |i| data << [ 10.0 + i * 0.1, 0.0 ] }
      20.times { |i| data << [ 20.0 + i * 0.1, 0.0 ] }

      # Run KMeans with 6 clusters
      kmeans = Broadlistening::KMeans.new(n_clusters: 6, random_state: 42)
      kmeans.fit(data)

      # Merge down to 3 clusters
      merged_labels = described_class.merge(
        kmeans.centroids,
        kmeans.labels,
        3
      )

      expect(merged_labels.uniq.size).to eq(3)
      expect(merged_labels.size).to eq(data.size)
    end
  end
end
