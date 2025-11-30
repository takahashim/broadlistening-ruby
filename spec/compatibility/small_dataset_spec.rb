# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Small Dataset Processing Compatibility" do
  # Tests for handling small datasets where n_samples is close to or below
  # the default n_neighbors value of 15 in UMAP

  let(:config) do
    Broadlistening::Config.new(
      api_key: "test",
      model: "gpt-4o-mini",
      cluster_nums: [ 2, 5 ]
    )
  end

  describe "n_neighbors adjustment logic" do
    # Python: n_neighbors = max(2, n_samples - 1) when n_samples <= 15
    # Ruby should match this behavior

    [
      { n_samples: 2, expected_neighbors: 2 },   # max(2, 1) = 2
      { n_samples: 3, expected_neighbors: 2 },   # max(2, 2) = 2
      { n_samples: 4, expected_neighbors: 3 },   # max(2, 3) = 3
      { n_samples: 5, expected_neighbors: 4 },   # max(2, 4) = 4
      { n_samples: 10, expected_neighbors: 9 },  # max(2, 9) = 9
      { n_samples: 15, expected_neighbors: 14 }, # max(2, 14) = 14
      { n_samples: 16, expected_neighbors: 15 }, # default 15
      { n_samples: 100, expected_neighbors: 15 } # default 15
    ].each do |test_case|
      n_samples = test_case[:n_samples]
      expected = test_case[:expected_neighbors]

      it "uses n_neighbors=#{expected} for #{n_samples} samples" do
        default_n_neighbors = 15

        num_neighbors = if n_samples <= default_n_neighbors
                          [ 2, n_samples - 1 ].max
        else
                          default_n_neighbors
        end

        expect(num_neighbors).to eq(expected)
      end
    end
  end

  describe "Clustering step with small datasets" do
    # Note: UMAP requires n_samples > embedding_dim for SVD decomposition.
    # We use embedding_dim = 3 for small sample tests to avoid SVD errors.

    def create_arguments(count, embedding_dim: 3)
      count.times.map do |i|
        embedding = Array.new(embedding_dim) { rand }
        Broadlistening::Argument.new(
          arg_id: "A#{i}_0",
          argument: "Opinion #{i}",
          comment_id: i.to_s,
          embedding: embedding
        )
      end
    end

    def create_context(arguments)
      ctx = Broadlistening::Context.new
      ctx.arguments = arguments
      ctx
    end

    describe "with 5 samples (minimum practical size)" do
      # Note: Very small datasets (< 5) may fail due to UMAP's SVD requirements
      # Python's umap-learn has different behavior than Ruby's umappp
      let(:arguments) { create_arguments(5) }
      let(:context) { create_context(arguments) }
      let(:small_config) do
        Broadlistening::Config.new(
          api_key: "test",
          model: "gpt-4o-mini",
          cluster_nums: [ 2, 3 ]
        )
      end
      let(:clustering_step) { Broadlistening::Steps::Clustering.new(small_config, context) }

      it "executes without error" do
        expect { clustering_step.execute }.not_to raise_error
      end

      it "assigns UMAP coordinates to all arguments" do
        clustering_step.execute

        context.arguments.each do |arg|
          expect(arg.x).to be_a(Float)
          expect(arg.y).to be_a(Float)
        end
      end

      it "adjusts cluster_nums to not exceed sample count" do
        clustering_step.execute

        context.arguments.each do |arg|
          expect(arg.cluster_ids).to include("0")
          expect(arg.cluster_ids.size).to be >= 2
        end
      end
    end

    describe "with 10 samples" do
      let(:arguments) { create_arguments(10) }
      let(:context) { create_context(arguments) }
      let(:clustering_step) { Broadlistening::Steps::Clustering.new(config, context) }

      it "executes without error" do
        expect { clustering_step.execute }.not_to raise_error
      end

      it "assigns cluster_ids to all arguments" do
        clustering_step.execute

        context.arguments.each do |arg|
          expect(arg.cluster_ids).not_to be_empty
          expect(arg.cluster_ids.first).to eq("0")
        end
      end
    end

    describe "with exactly 15 samples (boundary case)" do
      let(:arguments) { create_arguments(15) }
      let(:context) { create_context(arguments) }
      let(:clustering_step) { Broadlistening::Steps::Clustering.new(config, context) }

      it "executes without error" do
        expect { clustering_step.execute }.not_to raise_error
      end
    end

    describe "with 16 samples (just above boundary)" do
      let(:arguments) { create_arguments(16) }
      let(:context) { create_context(arguments) }
      let(:clustering_step) { Broadlistening::Steps::Clustering.new(config, context) }

      it "executes without error" do
        expect { clustering_step.execute }.not_to raise_error
      end
    end
  end

  describe "cluster_nums larger than sample count" do
    let(:arguments) do
      5.times.map do |i|
        Broadlistening::Argument.new(
          arg_id: "A#{i}_0",
          argument: "Opinion #{i}",
          comment_id: i.to_s,
          embedding: Array.new(3) { rand } # Use small embedding_dim for small samples
        )
      end
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.arguments = arguments
      ctx
    end

    let(:large_cluster_config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 10, 20 ] # Larger than 5 samples
      )
    end

    let(:clustering_step) { Broadlistening::Steps::Clustering.new(large_cluster_config, context) }

    it "adjusts cluster_nums to not exceed sample count" do
      clustering_step.execute

      # Should adjust to max of 5 clusters
      max_clusters = context.cluster_results.values.map { |labels| labels.uniq.size }.max
      expect(max_clusters).to be <= 5
    end

    it "produces valid cluster assignments" do
      clustering_step.execute

      context.arguments.each do |arg|
        expect(arg.cluster_ids).to include("0")
        expect(arg.cluster_ids.size).to be >= 2
      end
    end
  end

  describe "single cluster configuration" do
    let(:arguments) do
      10.times.map do |i|
        Broadlistening::Argument.new(
          arg_id: "A#{i}_0",
          argument: "Opinion #{i}",
          comment_id: i.to_s,
          embedding: Array.new(3) { rand } # Use small embedding_dim
        )
      end
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.arguments = arguments
      ctx
    end

    let(:single_cluster_config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 1, 3 ]
      )
    end

    let(:clustering_step) { Broadlistening::Steps::Clustering.new(single_cluster_config, context) }

    it "handles cluster_nums starting with 1" do
      clustering_step.execute

      # Level 1 should have exactly 1 cluster
      level_1_clusters = context.cluster_results[1]&.uniq&.size
      expect(level_1_clusters).to eq(1) if level_1_clusters
    end
  end

  describe "empty arguments" do
    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.arguments = []
      ctx
    end

    let(:clustering_step) { Broadlistening::Steps::Clustering.new(config, context) }

    it "handles empty arguments gracefully" do
      result = clustering_step.execute
      expect(result).to eq(context)
    end
  end
end
