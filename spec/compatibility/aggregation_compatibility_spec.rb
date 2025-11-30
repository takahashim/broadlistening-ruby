# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Aggregation Compatibility" do
  # Load Python-generated fixtures
  let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }

  let(:python_result) do
    JSON.parse(File.read(File.join(fixtures_dir, "hierarchical_result.json")))
  end

  let(:python_args_csv) do
    CSV.read(File.join(fixtures_dir, "args.csv"), headers: true)
  end

  let(:python_clusters_csv) do
    CSV.read(File.join(fixtures_dir, "hierarchical_clusters.csv"), headers: true)
  end

  let(:python_labels_csv) do
    CSV.read(File.join(fixtures_dir, "hierarchical_merge_labels.csv"), headers: true)
  end

  let(:python_relations_csv) do
    CSV.read(File.join(fixtures_dir, "relations.csv"), headers: true)
  end

  describe "Ruby Aggregation step output" do
    # Setup Ruby context with Python intermediate data
    let(:config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 5, 15 ]
      )
    end

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

    let(:arguments) do
      python_clusters_csv.map do |row|
        cluster_columns = python_clusters_csv.headers.select { |h| h.start_with?("cluster-level-") }
        cluster_ids = [ "0" ] + cluster_columns.map { |col| row[col] }

        # Find comment_id from relations
        relation = python_relations_csv.find { |r| r["arg-id"] == row["arg-id"] }
        comment_id = relation ? relation["comment-id"] : row["arg-id"].match(/A(\d+)_/)[1]

        Broadlistening::Argument.new(
          arg_id: row["arg-id"],
          argument: row["argument"],
          comment_id: comment_id,
          x: row["x"].to_f,
          y: row["y"].to_f,
          cluster_ids: cluster_ids
        )
      end
    end

    let(:labels) do
      python_labels_csv.each_with_object({}) do |row, hash|
        hash[row["id"]] = Broadlistening::ClusterLabel.new(
          cluster_id: row["id"],
          level: row["level"].to_i,
          label: row["label"],
          description: row["description"]
        )
      end
    end

    let(:cluster_results) do
      cluster_columns = python_clusters_csv.headers.select { |h| h.start_with?("cluster-level-") }

      cluster_columns.each_with_index.each_with_object({}) do |(col, idx), results|
        level = idx + 1
        results[level] = python_clusters_csv.map do |row|
          # Extract the numeric part after the underscore
          row[col].split("_").last.to_i
        end
      end
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx.arguments = arguments
      ctx.labels = labels
      ctx.cluster_results = cluster_results
      ctx.overview = "Test overview for compatibility testing."
      ctx
    end

    let(:ruby_step) { Broadlistening::Steps::Aggregation.new(config, context) }

    let(:ruby_result) do
      ruby_step.execute
      context.result.to_h
    end

    describe "Top-level structure" do
      it "has all required keys" do
        expected_keys = %i[arguments clusters comments propertyMap translations overview config]
        expect(ruby_result.keys).to include(*expected_keys)
      end

      it "has same number of arguments as Python" do
        expect(ruby_result[:arguments].size).to eq(python_result["arguments"].size)
      end

      it "has same number of clusters as Python" do
        expect(ruby_result[:clusters].size).to eq(python_result["clusters"].size)
      end
    end

    describe "Arguments format compatibility" do
      it "has correct arg_id format" do
        ruby_result[:arguments].each do |arg|
          expect(arg[:arg_id]).to match(/^A\d+_\d+$/),
            "Invalid arg_id format: #{arg[:arg_id]}"
        end
      end

      it "has comment_id as integer" do
        ruby_result[:arguments].each do |arg|
          expect(arg[:comment_id]).to be_a(Integer),
            "comment_id should be Integer, got #{arg[:comment_id].class}"
        end
      end

      it "has numeric coordinates" do
        ruby_result[:arguments].each do |arg|
          expect(arg[:x]).to be_a(Numeric)
          expect(arg[:y]).to be_a(Numeric)
        end
      end

      it "has cluster_ids as array of strings" do
        ruby_result[:arguments].each do |arg|
          expect(arg[:cluster_ids]).to be_an(Array)
          expect(arg[:cluster_ids]).to all(be_a(String))
        end
      end

      it "has cluster_ids starting with '0'" do
        ruby_result[:arguments].each do |arg|
          expect(arg[:cluster_ids].first).to eq("0")
        end
      end

      it "has p value as integer" do
        ruby_result[:arguments].each do |arg|
          expect(arg[:p]).to eq(0)
        end
      end

      it "matches Python arg_id ordering" do
        ruby_ids = ruby_result[:arguments].map { |a| a[:arg_id] }
        python_ids = python_result["arguments"].map { |a| a["arg_id"] }

        # They should have the same set of arg_ids
        expect(ruby_ids.sort).to eq(python_ids.sort)
      end
    end

    describe "Clusters format compatibility" do
      it "has root cluster at level 0" do
        root = ruby_result[:clusters].find { |c| c[:level] == 0 }
        expect(root).not_to be_nil
        expect(root[:id]).to eq("0")
        expect(root[:parent]).to eq("")
      end

      it "has required keys for each cluster" do
        required_keys = %i[level id label takeaway value parent]
        ruby_result[:clusters].each do |cluster|
          expect(cluster.keys).to include(*required_keys),
            "Cluster #{cluster[:id]} missing keys: #{required_keys - cluster.keys}"
        end
      end

      it "has correct cluster ID format" do
        ruby_result[:clusters].each do |cluster|
          if cluster[:level] == 0
            expect(cluster[:id]).to eq("0")
          else
            expect(cluster[:id]).to match(/^\d+_\d+$/)
          end
        end
      end

      it "has valid parent references" do
        cluster_ids = ruby_result[:clusters].map { |c| c[:id] }

        ruby_result[:clusters].each do |cluster|
          next if cluster[:level] == 0

          expect(cluster_ids).to include(cluster[:parent]),
            "Cluster #{cluster[:id]} has invalid parent #{cluster[:parent]}"
        end
      end

      it "has correct value counts" do
        root = ruby_result[:clusters].find { |c| c[:level] == 0 }
        expect(root[:value]).to eq(ruby_result[:arguments].size)
      end

      it "matches Python hierarchy levels" do
        ruby_levels = ruby_result[:clusters].map { |c| c[:level] }.uniq.sort
        python_levels = python_result["clusters"].map { |c| c["level"] }.uniq.sort
        expect(ruby_levels).to eq(python_levels)
      end
    end

    describe "propertyMap structure" do
      it "is a hash" do
        expect(ruby_result[:propertyMap]).to be_a(Hash)
      end
    end

    describe "translations structure" do
      it "is a hash" do
        expect(ruby_result[:translations]).to be_a(Hash)
      end
    end

    describe "overview" do
      it "is a non-empty string" do
        expect(ruby_result[:overview]).to be_a(String)
        expect(ruby_result[:overview]).not_to be_empty
      end
    end

    describe "config" do
      it "is a hash" do
        expect(ruby_result[:config]).to be_a(Hash)
      end
    end

    describe "JSON serialization" do
      it "can be serialized to valid JSON" do
        json_string = JSON.generate(ruby_result)
        expect { JSON.parse(json_string) }.not_to raise_error
      end

      it "produces JSON that validates against schema" do
        json_string = JSON.generate(ruby_result)
        parsed = JSON.parse(json_string)

        errors = Broadlistening::Compatibility.validate_with_schema(parsed)
        expect(errors).to be_empty, "Schema validation errors: #{errors.map { |e| e[:message] }.join(', ')}"
      end
    end

    describe "Data consistency between Python and Ruby" do
      it "produces same cluster level counts" do
        ruby_level_counts = ruby_result[:clusters].group_by { |c| c[:level] }.transform_values(&:size)
        python_level_counts = python_result["clusters"].group_by { |c| c["level"] }.transform_values(&:size)

        expect(ruby_level_counts).to eq(python_level_counts)
      end

      it "produces same root cluster value" do
        ruby_root = ruby_result[:clusters].find { |c| c[:level] == 0 }
        python_root = python_result["clusters"].find { |c| c["level"] == 0 }

        expect(ruby_root[:value]).to eq(python_root["value"])
      end
    end
  end
end
