# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Kouchou-AI Compatibility" do
  # Path to fixture file (copied from Kouchou-AI Python output)
  let(:python_output_path) do
    File.expand_path("../fixtures/hierarchical_result.json", __dir__)
  end

  let(:python_output) do
    JSON.parse(File.read(python_output_path))
  end

  describe "Python output structure validation" do
    it "has valid output structure" do
      errors = Broadlistening::Compatibility.validate_output(python_output)
      expect(errors).to be_empty, "Validation errors: #{errors.join(', ')}"
    end

    it "contains expected top-level keys" do
      expected_keys = %w[arguments clusters comments propertyMap translations overview config]
      expect(python_output.keys).to include(*expected_keys)
    end
  end

  describe "JSON Schema validation" do
    it "validates against JSON Schema" do
      errors = Broadlistening::Compatibility.validate_with_schema(python_output)
      expect(errors).to be_empty, "Schema validation errors: #{errors.map { |e| e[:message] }.join(', ')}"
    end

    it "passes valid_schema? check" do
      expect(Broadlistening::Compatibility.valid_schema?(python_output)).to be true
    end
  end

  describe "Arguments structure" do
    let(:arguments) { python_output["arguments"] }
    let(:sample_arg) { arguments.first }

    it "has arguments array" do
      expect(arguments).to be_an(Array)
      expect(arguments).not_to be_empty
    end

    it "has required argument keys" do
      required_keys = %w[arg_id argument comment_id x y cluster_ids]
      expect(sample_arg.keys).to include(*required_keys)
    end

    it "has valid arg_id format (A{comment_id}_{index})" do
      expect(sample_arg["arg_id"]).to match(/^A\d+_\d+$/)
    end

    it "has numeric coordinates" do
      expect(sample_arg["x"]).to be_a(Numeric)
      expect(sample_arg["y"]).to be_a(Numeric)
    end

    it "has cluster_ids as array of strings" do
      expect(sample_arg["cluster_ids"]).to be_an(Array)
      expect(sample_arg["cluster_ids"]).to all(be_a(String))
    end

    it "has hierarchical cluster_ids format ({level}_{index})" do
      cluster_ids = sample_arg["cluster_ids"]
      # First should be root "0"
      expect(cluster_ids.first).to eq("0")
      # Others should be level_index format
      cluster_ids[1..].each do |id|
        expect(id).to match(/^\d+_\d+$/)
      end
    end
  end

  describe "Clusters structure" do
    let(:clusters) { python_output["clusters"] }
    let(:sample_cluster) { clusters.first }

    it "has clusters array" do
      expect(clusters).to be_an(Array)
      expect(clusters).not_to be_empty
    end

    it "has required cluster keys" do
      required_keys = %w[level id label takeaway value parent]
      expect(sample_cluster.keys).to include(*required_keys)
    end

    it "has root cluster at level 0" do
      root = clusters.find { |c| c["level"] == 0 }
      expect(root).not_to be_nil
      expect(root["id"]).to eq("0")
      expect(root["parent"]).to eq("")
    end

    it "has hierarchical levels" do
      levels = clusters.map { |c| c["level"] }.uniq.sort
      expect(levels).to include(0)
      expect(levels.size).to be > 1
    end

    it "has valid parent references" do
      clusters.each do |cluster|
        next if cluster["level"] == 0 # Root has no parent

        parent_id = cluster["parent"]
        parent = clusters.find { |c| c["id"] == parent_id }
        expect(parent).not_to be_nil, "Parent #{parent_id} not found for cluster #{cluster['id']}"
        expect(parent["level"]).to be < cluster["level"]
      end
    end

    it "has positive value counts" do
      clusters.each do |cluster|
        expect(cluster["value"]).to be_a(Integer)
        expect(cluster["value"]).to be >= 0
      end
    end
  end

  describe "Overview" do
    it "has non-empty overview" do
      expect(python_output["overview"]).to be_a(String)
      expect(python_output["overview"].strip).not_to be_empty
    end
  end

  describe "Config structure" do
    let(:config) { python_output["config"] }

    it "has config hash" do
      expect(config).to be_a(Hash)
    end

    it "has cluster_nums configuration" do
      cluster_nums = config.dig("hierarchical_clustering", "cluster_nums")
      expect(cluster_nums).to be_an(Array) if cluster_nums
    end
  end

  describe "Data consistency" do
    it "root cluster value equals total arguments" do
      root = python_output["clusters"].find { |c| c["level"] == 0 }
      total_args = python_output["arguments"].size
      expect(root["value"]).to eq(total_args)
    end

    it "all arguments reference existing clusters" do
      cluster_ids = python_output["clusters"].map { |c| c["id"] }

      python_output["arguments"].each do |arg|
        arg["cluster_ids"].each do |cid|
          expect(cluster_ids).to include(cid),
            "Argument #{arg['arg_id']} references non-existent cluster #{cid}"
        end
      end
    end
  end
end
