# frozen_string_literal: true

RSpec.describe Broadlistening::DensityCalculator do
  describe ".calculate" do
    it "calculates density for normal cluster" do
      points = [ [ 0.0, 0.0 ], [ 1.0, 0.0 ], [ 0.0, 1.0 ], [ 1.0, 1.0 ] ]
      density = described_class.calculate(points)

      # Expected: 1 / 0.7071067811865476 ≈ 1.414213562173095
      expect(density).to be_within(1e-10).of(1.414213562173095)
    end

    it "calculates density for single point" do
      points = [ [ 5.0, 5.0 ] ]
      density = described_class.calculate(points)

      # Single point: avg_distance = 0, density = 1 / (0 + 1e-10) = 1e10
      expect(density).to eq(1e10)
    end

    it "calculates density for two points" do
      points = [ [ 0.0, 0.0 ], [ 10.0, 0.0 ] ]
      density = described_class.calculate(points)

      # Two points: center = (5, 0), distances = [5, 5], avg = 5
      # density = 1 / (5 + 1e-10) ≈ 0.2
      expect(density).to be_within(1e-10).of(0.199999999996)
    end

    it "calculates density for points at same location" do
      points = [ [ 3.0, 3.0 ], [ 3.0, 3.0 ], [ 3.0, 3.0 ] ]
      density = described_class.calculate(points)

      # All same: avg_distance = 0, density = 1e10
      expect(density).to eq(1e10)
    end

    it "calculates density for cluster with varying spread" do
      points = [ [ 0.0, 0.0 ], [ 0.1, 0.1 ], [ 0.2, 0.0 ], [ -0.1, 0.1 ] ]
      density = described_class.calculate(points)

      expect(density).to be_within(1e-10).of(8.740320481337102)
    end

    it "handles Numo::DFloat input" do
      points = Numo::DFloat[[ 0.0, 0.0 ], [ 1.0, 0.0 ], [ 0.0, 1.0 ], [ 1.0, 1.0 ]]
      density = described_class.calculate(points)

      expect(density).to be_within(1e-10).of(1.414213562173095)
    end

    it "handles empty points array" do
      points = []
      density = described_class.calculate(points)

      expect(density).to eq(1e10) # Returns 1/EPSILON for empty
    end
  end

  describe ".calculate_with_ranks" do
    let(:clusters) do
      {
        "1_0" => { points: [ [ 0.0, 0.0 ], [ 1.0, 0.0 ] ], level: 1 },      # spread = 1.0
        "1_1" => { points: [ [ 0.0, 0.0 ], [ 0.1, 0.0 ] ], level: 1 },      # spread = 0.1 (denser)
        "2_0" => { points: [ [ 0.0, 0.0 ], [ 2.0, 0.0 ] ], level: 2 },      # spread = 2.0
        "2_1" => { points: [ [ 0.0, 0.0 ], [ 0.5, 0.0 ] ], level: 2 }       # spread = 0.5 (denser)
      }
    end

    it "calculates density for each cluster" do
      result = described_class.calculate_with_ranks(clusters)

      expect(result["1_0"].density).to be_a(Float)
      expect(result["1_1"].density).to be_a(Float)
      expect(result["2_0"].density).to be_a(Float)
      expect(result["2_1"].density).to be_a(Float)
    end

    it "ranks clusters within each level" do
      result = described_class.calculate_with_ranks(clusters)

      # Level 1: 1_1 is denser (higher density) -> rank 1
      expect(result["1_1"].density_rank).to eq(1)
      expect(result["1_0"].density_rank).to eq(2)

      # Level 2: 2_1 is denser -> rank 1
      expect(result["2_1"].density_rank).to eq(1)
      expect(result["2_0"].density_rank).to eq(2)
    end

    it "calculates density_rank_percentile within each level" do
      result = described_class.calculate_with_ranks(clusters)

      # Level 1 has 2 clusters: ranks 1, 2 -> percentiles 0.5, 1.0
      expect(result["1_1"].density_rank_percentile).to eq(0.5)
      expect(result["1_0"].density_rank_percentile).to eq(1.0)

      # Level 2 has 2 clusters: ranks 1, 2 -> percentiles 0.5, 1.0
      expect(result["2_1"].density_rank_percentile).to eq(0.5)
      expect(result["2_0"].density_rank_percentile).to eq(1.0)
    end

    it "handles single cluster in a level" do
      single_cluster = {
        "1_0" => { points: [ [ 0.0, 0.0 ], [ 1.0, 0.0 ] ], level: 1 }
      }
      result = described_class.calculate_with_ranks(single_cluster)

      expect(result["1_0"].density_rank).to eq(1)
      expect(result["1_0"].density_rank_percentile).to eq(1.0)
    end

    it "returns empty hash for empty input" do
      result = described_class.calculate_with_ranks({})
      expect(result).to eq({})
    end
  end
end
