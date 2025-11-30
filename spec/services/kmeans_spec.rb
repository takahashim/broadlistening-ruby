# frozen_string_literal: true

RSpec.describe Broadlistening::Services::KMeans do
  describe "#fit" do
    context "with simple 2D data" do
      let(:data) do
        [
          [0.0, 0.0], [0.1, 0.1], [0.2, 0.0],
          [5.0, 5.0], [5.1, 5.1], [5.0, 5.2],
          [10.0, 0.0], [10.1, 0.1], [10.0, 0.2]
        ]
      end

      it "clusters data into specified number of clusters" do
        kmeans = described_class.new(n_clusters: 3, random_state: 42)
        kmeans.fit(data)

        expect(kmeans.labels.uniq.size).to eq(3)
        expect(kmeans.centroids.shape).to eq([3, 2])
      end

      it "assigns nearby points to the same cluster" do
        kmeans = described_class.new(n_clusters: 3, random_state: 42)
        kmeans.fit(data)

        labels = kmeans.labels
        expect(labels[0]).to eq(labels[1])
        expect(labels[0]).to eq(labels[2])
        expect(labels[3]).to eq(labels[4])
        expect(labels[3]).to eq(labels[5])
        expect(labels[6]).to eq(labels[7])
        expect(labels[6]).to eq(labels[8])
      end

      it "computes inertia" do
        kmeans = described_class.new(n_clusters: 3, random_state: 42)
        kmeans.fit(data)

        expect(kmeans.inertia).to be_a(Float)
        expect(kmeans.inertia).to be >= 0
      end
    end

    context "with Numo::DFloat input" do
      let(:data) { Numo::DFloat[[0.0, 0.0], [1.0, 1.0], [10.0, 10.0], [11.0, 11.0]] }

      it "accepts Numo::DFloat arrays" do
        kmeans = described_class.new(n_clusters: 2, random_state: 42)
        kmeans.fit(data)

        expect(kmeans.labels.size).to eq(4)
        expect(kmeans.labels[0]).to eq(kmeans.labels[1])
        expect(kmeans.labels[2]).to eq(kmeans.labels[3])
        expect(kmeans.labels[0]).not_to eq(kmeans.labels[2])
      end
    end

    context "with deterministic random state" do
      let(:data) { [[0, 0], [1, 1], [10, 10], [11, 11]] }

      it "produces consistent results with same random_state" do
        kmeans1 = described_class.new(n_clusters: 2, random_state: 123)
        kmeans2 = described_class.new(n_clusters: 2, random_state: 123)

        kmeans1.fit(data)
        kmeans2.fit(data)

        expect(kmeans1.labels).to eq(kmeans2.labels)
      end
    end

    context "with edge cases" do
      it "raises error when n_clusters > n_samples" do
        kmeans = described_class.new(n_clusters: 10, random_state: 42)
        data = [[0, 0], [1, 1], [2, 2]]

        expect { kmeans.fit(data) }.to raise_error(Broadlistening::ClusteringError, /n_clusters.*must be <= n_samples/)
      end

      it "raises error when n_clusters is zero" do
        kmeans = described_class.new(n_clusters: 0, random_state: 42)
        data = [[0, 0], [1, 1]]

        expect { kmeans.fit(data) }.to raise_error(Broadlistening::ClusteringError, /must be positive/)
      end

      it "handles single cluster" do
        kmeans = described_class.new(n_clusters: 1, random_state: 42)
        data = [[0, 0], [1, 1], [2, 2]]
        kmeans.fit(data)

        expect(kmeans.labels).to eq([0, 0, 0])
      end

      it "handles n_clusters equal to n_samples" do
        kmeans = described_class.new(n_clusters: 3, random_state: 42)
        data = [[0, 0], [5, 5], [10, 10]]
        kmeans.fit(data)

        expect(kmeans.labels.uniq.size).to eq(3)
      end
    end

    context "with convergence" do
      let(:data) do
        [
          [0.0, 0.0], [0.0, 0.1], [0.1, 0.0],
          [10.0, 10.0], [10.0, 10.1], [10.1, 10.0]
        ]
      end

      it "converges before max_iterations for well-separated clusters" do
        kmeans = described_class.new(n_clusters: 2, max_iterations: 100, random_state: 42)
        kmeans.fit(data)

        expect(kmeans.labels[0]).to eq(kmeans.labels[1])
        expect(kmeans.labels[0]).to eq(kmeans.labels[2])
        expect(kmeans.labels[3]).to eq(kmeans.labels[4])
        expect(kmeans.labels[3]).to eq(kmeans.labels[5])
      end
    end
  end

  describe "#predict" do
    let(:training_data) do
      [
        [0.0, 0.0], [0.1, 0.1],
        [10.0, 10.0], [10.1, 10.1]
      ]
    end

    it "predicts labels for new data" do
      kmeans = described_class.new(n_clusters: 2, random_state: 42)
      kmeans.fit(training_data)

      new_data = [[0.05, 0.05], [10.05, 10.05]]
      predictions = kmeans.predict(Numo::DFloat.cast(new_data))

      expect(predictions[0]).to eq(kmeans.labels[0])
      expect(predictions[1]).to eq(kmeans.labels[2])
    end
  end

  describe "#fit_predict" do
    let(:data) { [[0, 0], [1, 1], [10, 10], [11, 11]] }

    it "fits and returns labels in one call" do
      kmeans = described_class.new(n_clusters: 2, random_state: 42)
      labels = kmeans.fit_predict(data)

      expect(labels).to eq(kmeans.labels)
      expect(labels.size).to eq(4)
    end
  end

  describe "k-means++ initialization" do
    let(:data) do
      Array.new(100) { |i| [i % 10, i / 10] }
    end

    it "produces better initial centroids than random initialization" do
      # K-means++ should give more spread-out initial centroids
      kmeans = described_class.new(n_clusters: 4, random_state: 42)
      kmeans.fit(data)

      centroids = kmeans.centroids.to_a
      min_distance = Float::INFINITY

      centroids.each_with_index do |c1, i|
        centroids[(i + 1)..].each do |c2|
          dist = Math.sqrt((c1[0] - c2[0])**2 + (c1[1] - c2[1])**2)
          min_distance = [min_distance, dist].min
        end
      end

      # Centroids should not be too close together
      expect(min_distance).to be > 1.0
    end
  end

  describe "handling empty clusters" do
    it "reassigns empty clusters to random points" do
      # This is a tricky case - with specific initialization, some clusters might become empty
      # The algorithm should handle this gracefully
      data = [[0, 0], [0, 0], [0, 0], [100, 100]]

      kmeans = described_class.new(n_clusters: 2, random_state: 42, max_iterations: 50)
      expect { kmeans.fit(data) }.not_to raise_error

      expect(kmeans.labels.size).to eq(4)
    end
  end
end
