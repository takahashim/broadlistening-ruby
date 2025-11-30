# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Pipeline E2E Compatibility" do
  # This test runs the full Ruby pipeline with mock LLM responses
  # using Python-generated fixture data to verify end-to-end compatibility

  let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }

  let(:python_result) do
    JSON.parse(File.read(File.join(fixtures_dir, "hierarchical_result.json")))
  end

  let(:python_embeddings) do
    JSON.parse(File.read(File.join(fixtures_dir, "embeddings.json")))
  end

  let(:python_args_csv) do
    CSV.read(File.join(fixtures_dir, "args.csv"), headers: true)
  end

  let(:python_relations_csv) do
    CSV.read(File.join(fixtures_dir, "relations.csv"), headers: true)
  end

  let(:python_labels_csv) do
    CSV.read(File.join(fixtures_dir, "hierarchical_merge_labels.csv"), headers: true)
  end

  let(:python_overview) do
    File.read(File.join(fixtures_dir, "hierarchical_overview.txt"))
  end

  describe "Full pipeline with mocked LLM" do
    let(:output_dir) { Dir.mktmpdir("pipeline_e2e_test") }

    let(:config) do
      Broadlistening::Config.new(
        api_key: "test-api-key",
        model: "gpt-4o-mini",
        embedding_model: "text-embedding-3-small",
        cluster_nums: [ 5, 15 ]
      )
    end

    # Build comments from fixture data
    let(:comments) do
      comment_ids = python_relations_csv.map { |r| r["comment-id"].to_s }.uniq

      comment_ids.map do |id|
        Broadlistening::Comment.new(
          id: id,
          body: "Test comment #{id}",
          proposal_id: "test"
        )
      end
    end

    # Build arguments with embeddings from Python fixtures
    let(:arguments_with_embeddings) do
      embeddings_map = python_embeddings.each_with_object({}) do |e, hash|
        hash[e["arg_id"]] = e["embedding"]
      end

      python_args_csv.map do |row|
        # Find comment_id from relations
        relation = python_relations_csv.find { |r| r["arg-id"] == row["arg-id"] }
        comment_id = relation ? relation["comment-id"] : row["arg-id"].match(/A(\d+)_/)[1]

        Broadlistening::Argument.new(
          arg_id: row["arg-id"],
          argument: row["argument"],
          comment_id: comment_id,
          embedding: embeddings_map[row["arg-id"]]
        )
      end
    end

    # Mock labels from Python fixtures
    let(:mock_labels) do
      python_labels_csv.each_with_object({}) do |row, hash|
        hash[row["id"]] = Broadlistening::ClusterLabel.new(
          cluster_id: row["id"],
          level: row["level"].to_i,
          label: row["label"],
          description: row["description"]
        )
      end
    end

    after do
      FileUtils.rm_rf(output_dir)
    end

    context "Clustering step" do
      let(:context) do
        ctx = Broadlistening::Context.new
        ctx.comments = comments
        ctx.arguments = arguments_with_embeddings
        ctx.output_dir = output_dir
        ctx
      end

      let(:clustering_step) { Broadlistening::Steps::Clustering.new(config, context) }

      it "produces valid clustering output" do
        clustering_step.execute

        # Check that all arguments have coordinates
        context.arguments.each do |arg|
          expect(arg.x).to be_a(Numeric)
          expect(arg.y).to be_a(Numeric)
          expect(arg.cluster_ids).to be_an(Array)
          expect(arg.cluster_ids.first).to eq("0")
        end
      end

      it "produces same number of hierarchy levels as Python" do
        clustering_step.execute

        ruby_levels = context.arguments.first.cluster_ids.size
        python_levels = python_result["arguments"].first["cluster_ids"].size

        expect(ruby_levels).to eq(python_levels)
      end

      it "produces similar coordinate ranges" do
        clustering_step.execute

        ruby_x_range = context.arguments.map(&:x).minmax
        ruby_y_range = context.arguments.map(&:y).minmax

        python_x_range = python_result["arguments"].map { |a| a["x"] }.minmax
        python_y_range = python_result["arguments"].map { |a| a["y"] }.minmax

        # UMAP coordinates should be in similar ranges (allowing for implementation differences)
        # Note: Different UMAP implementations may produce different absolute values
        # but the relative structure should be similar
        expect(ruby_x_range[1] - ruby_x_range[0]).to be_within(20).of(python_x_range[1] - python_x_range[0])
        expect(ruby_y_range[1] - ruby_y_range[0]).to be_within(20).of(python_y_range[1] - python_y_range[0])
      end

      it "produces clusters with values summing correctly" do
        clustering_step.execute

        cluster_counts = {}
        context.arguments.each do |arg|
          arg.cluster_ids.each do |cid|
            cluster_counts[cid] ||= 0
            cluster_counts[cid] += 1
          end
        end

        # Root cluster should contain all arguments
        expect(cluster_counts["0"]).to eq(context.arguments.size)
      end
    end

    context "Full pipeline simulation" do
      let(:context) do
        ctx = Broadlistening::Context.new
        ctx.comments = comments
        ctx.arguments = arguments_with_embeddings
        ctx.output_dir = output_dir
        ctx
      end

      it "produces structurally valid result" do
        # Run clustering
        clustering_step = Broadlistening::Steps::Clustering.new(config, context)
        clustering_step.execute

        # Mock labels (skip LLM steps)
        context.labels = mock_labels
        context.overview = python_overview

        # Run aggregation
        aggregation_step = Broadlistening::Steps::Aggregation.new(config, context)
        aggregation_step.execute

        result = context.result.to_h

        # Validate structure
        expect(result).to have_key(:arguments)
        expect(result).to have_key(:clusters)
        expect(result).to have_key(:overview)
        expect(result).to have_key(:config)

        # Validate against schema
        json_string = JSON.generate(result)
        parsed = JSON.parse(json_string)
        errors = Broadlistening::Compatibility.validate_with_schema(parsed)
        expect(errors).to be_empty, "Schema validation errors: #{errors.map { |e| e[:message] }.join(', ')}"
      end

      it "produces compatible output structure" do
        # Run clustering
        clustering_step = Broadlistening::Steps::Clustering.new(config, context)
        clustering_step.execute

        # Mock labels
        context.labels = mock_labels
        context.overview = python_overview

        # Run aggregation
        aggregation_step = Broadlistening::Steps::Aggregation.new(config, context)
        aggregation_step.execute

        result = context.result.to_h

        # Compare with Python output
        expect(result[:arguments].size).to eq(python_result["arguments"].size)

        # Same number of clusters at each level
        ruby_level_counts = result[:clusters].group_by { |c| c[:level] }.transform_values(&:size)
        python_level_counts = python_result["clusters"].group_by { |c| c["level"] }.transform_values(&:size)
        expect(ruby_level_counts).to eq(python_level_counts)
      end
    end
  end

  describe "ComparisonReport generation" do
    let(:ruby_output) do
      {
        "arguments" => python_result["arguments"],
        "clusters" => python_result["clusters"],
        "comments" => python_result["comments"],
        "propertyMap" => python_result["propertyMap"],
        "translations" => python_result["translations"],
        "overview" => python_result["overview"],
        "config" => python_result["config"],
        "comment_num" => python_result["comment_num"]
      }
    end

    it "reports compatible when outputs match" do
      report = Broadlistening::Compatibility.compare_outputs(
        python_output: python_result,
        ruby_output: ruby_output
      )

      expect(report.compatible?).to be true
      expect(report.differences).to be_empty
    end

    it "provides meaningful summary" do
      report = Broadlistening::Compatibility.compare_outputs(
        python_output: python_result,
        ruby_output: ruby_output
      )

      summary = report.summary
      expect(summary).to include("Compatibility Report")
      expect(summary).to include("COMPATIBLE")
    end

    context "when outputs differ" do
      let(:modified_ruby_output) do
        output = ruby_output.dup
        output["clusters"] = output["clusters"].select { |c| c["level"] < 2 }
        output
      end

      it "reports incompatible with details" do
        report = Broadlistening::Compatibility.compare_outputs(
          python_output: python_result,
          ruby_output: modified_ruby_output
        )

        expect(report.compatible?).to be false
        expect(report.differences).not_to be_empty
      end
    end
  end
end
