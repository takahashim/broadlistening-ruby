# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Density Calculation Compatibility" do
  let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }

  let(:reference_data) do
    JSON.parse(File.read(File.join(fixtures_dir, "density_reference.json")))
  end

  let(:clusters) { reference_data["clusters"] }
  let(:expected_results) { reference_data["expected_results"] }

  describe "DensityCalculator.calculate" do
    it "matches Python density calculation for each cluster" do
      clusters.each do |cluster_id, cluster_data|
        points = cluster_data["points"]
        ruby_density = Broadlistening::DensityCalculator.calculate(points)
        python_density = expected_results[cluster_id]["density"]

        expect(ruby_density).to be_within(1e-8).of(python_density),
          "Density mismatch for #{cluster_id}: Ruby=#{ruby_density}, Python=#{python_density}"
      end
    end
  end

  describe "DensityCalculator.calculate_with_ranks" do
    let(:cluster_points) { Broadlistening::DensityCalculator::ClusterPoints }

    let(:ruby_clusters) do
      clusters.map do |cluster_id, data|
        cluster_points.new(cluster_id: cluster_id, points: data["points"], level: data["level"])
      end
    end

    let(:ruby_results) do
      Broadlistening::DensityCalculator.calculate_with_ranks(ruby_clusters)
    end

    it "calculates same density values as Python" do
      expected_results.each do |cluster_id, expected|
        ruby_density = ruby_results[cluster_id].density
        python_density = expected["density"]

        expect(ruby_density).to be_within(1e-8).of(python_density),
          "Density mismatch for #{cluster_id}: Ruby=#{ruby_density}, Python=#{python_density}"
      end
    end

    it "assigns same density ranks as Python" do
      expected_results.each do |cluster_id, expected|
        ruby_rank = ruby_results[cluster_id].density_rank
        python_rank = expected["density_rank"]

        expect(ruby_rank).to eq(python_rank),
          "Rank mismatch for #{cluster_id}: Ruby=#{ruby_rank}, Python=#{python_rank}"
      end
    end

    it "calculates same density_rank_percentile as Python" do
      expected_results.each do |cluster_id, expected|
        ruby_percentile = ruby_results[cluster_id].density_rank_percentile
        python_percentile = expected["density_rank_percentile"]

        expect(ruby_percentile).to be_within(1e-10).of(python_percentile),
          "Percentile mismatch for #{cluster_id}: Ruby=#{ruby_percentile}, Python=#{python_percentile}"
      end
    end
  end

  describe "Edge cases" do
    describe "single point cluster" do
      it "produces very high density (1/epsilon)" do
        single_point = [ [ 5.0, 5.0 ] ]
        density = Broadlistening::DensityCalculator.calculate(single_point)

        # Python: 1 / (0 + 1e-10) = 1e10
        expect(density).to eq(1e10)
      end
    end

    describe "all points at same location" do
      it "produces very high density (1/epsilon)" do
        same_points = [ [ 3.0, 3.0 ], [ 3.0, 3.0 ], [ 3.0, 3.0 ] ]
        density = Broadlistening::DensityCalculator.calculate(same_points)

        expect(density).to eq(1e10)
      end
    end

    describe "two points" do
      it "calculates density based on distance between them" do
        two_points = [ [ 0.0, 0.0 ], [ 2.0, 0.0 ] ]
        density = Broadlistening::DensityCalculator.calculate(two_points)

        # Center = (1, 0), distances = [1, 1], avg = 1
        # density = 1 / (1 + 1e-10) ≈ 1.0
        expect(density).to be_within(1e-8).of(0.9999999999)
      end
    end

    describe "large spread cluster" do
      it "produces low density" do
        large_spread = [ [ 0.0, 0.0 ], [ 100.0, 0.0 ], [ 0.0, 100.0 ], [ 100.0, 100.0 ] ]
        density = Broadlistening::DensityCalculator.calculate(large_spread)

        # Large spread = large avg distance = low density
        expect(density).to be < 0.1
      end
    end

    describe "tight cluster" do
      it "produces high density" do
        tight_cluster = [ [ 0.0, 0.0 ], [ 0.01, 0.0 ], [ 0.0, 0.01 ], [ 0.01, 0.01 ] ]
        density = Broadlistening::DensityCalculator.calculate(tight_cluster)

        # Tight cluster = small avg distance = high density
        expect(density).to be > 100
      end
    end
  end

  describe "Numerical precision" do
    it "handles very small coordinates" do
      small_coords = [ [ 1e-10, 1e-10 ], [ 2e-10, 2e-10 ] ]
      density = Broadlistening::DensityCalculator.calculate(small_coords)

      expect(density).to be_a(Float)
      expect(density.finite?).to be true
    end

    it "handles large coordinates" do
      large_coords = [ [ 1e6, 1e6 ], [ 1e6 + 1, 1e6 + 1 ] ]
      density = Broadlistening::DensityCalculator.calculate(large_coords)

      expect(density).to be_a(Float)
      expect(density.finite?).to be true
    end
  end
end
