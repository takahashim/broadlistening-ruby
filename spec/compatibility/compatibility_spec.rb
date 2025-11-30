# frozen_string_literal: true

require "spec_helper"

RSpec.describe Broadlistening::Compatibility do
  describe ".validate_output" do
    context "with valid output" do
      let(:valid_output) do
        {
          "arguments" => [
            {
              "arg_id" => "A0_0",
              "argument" => "Test argument",
              "comment_id" => 0,
              "x" => 1.0,
              "y" => 2.0,
              "cluster_ids" => [ "0", "1_0" ]
            }
          ],
          "clusters" => [
            {
              "level" => 0,
              "id" => "0",
              "label" => "All",
              "takeaway" => "",
              "value" => 1,
              "parent" => ""
            }
          ],
          "comments" => {},
          "propertyMap" => {},
          "translations" => {},
          "overview" => "Test overview",
          "config" => {}
        }
      end

      it "returns empty errors array" do
        errors = described_class.validate_output(valid_output)
        expect(errors).to be_empty
      end

      it "returns true for valid_output?" do
        expect(described_class.valid_output?(valid_output)).to be true
      end
    end

    context "with missing top-level keys" do
      let(:invalid_output) do
        {
          "arguments" => [],
          "clusters" => []
        }
      end

      it "returns errors for missing keys" do
        errors = described_class.validate_output(invalid_output)
        expect(errors.first).to include("Missing top-level keys")
      end
    end

    context "with missing argument keys" do
      let(:output) do
        {
          "arguments" => [ { "arg_id" => "A0_0" } ],
          "clusters" => [],
          "comments" => {},
          "propertyMap" => {},
          "translations" => {},
          "overview" => "",
          "config" => {}
        }
      end

      it "returns errors for missing argument keys" do
        errors = described_class.validate_output(output)
        expect(errors.any? { |e| e.include?("Missing argument keys") }).to be true
      end
    end
  end

  describe ".compare_outputs" do
    let(:python_output) do
      {
        "arguments" => [
          {
            "arg_id" => "A0_0",
            "argument" => "Test",
            "comment_id" => 0,
            "x" => 1.0,
            "y" => 2.0,
            "p" => 0,
            "cluster_ids" => [ "0", "1_0", "2_5" ]
          }
        ],
        "clusters" => [
          { "level" => 0, "id" => "0", "label" => "All", "takeaway" => "", "value" => 10, "parent" => "" },
          { "level" => 1, "id" => "1_0", "label" => "Group A", "takeaway" => "Desc", "value" => 5, "parent" => "0" },
          { "level" => 2, "id" => "2_5", "label" => "Subgroup", "takeaway" => "Desc", "value" => 3, "parent" => "1_0" }
        ],
        "comments" => {},
        "propertyMap" => {},
        "translations" => {},
        "overview" => "Test overview",
        "config" => {}
      }
    end

    context "when outputs are compatible" do
      let(:ruby_output) { python_output.dup }

      it "returns compatible report" do
        report = described_class.compare_outputs(
          python_output: python_output,
          ruby_output: ruby_output
        )

        expect(report.compatible?).to be true
        expect(report.differences).to be_empty
      end

      it "collects stats correctly" do
        report = described_class.compare_outputs(
          python_output: python_output,
          ruby_output: ruby_output
        )

        expect(report.python_stats[:argument_count]).to eq(1)
        expect(report.python_stats[:cluster_count]).to eq(3)
        expect(report.python_stats[:cluster_levels]).to eq([ 0, 1, 2 ])
        expect(report.python_stats[:has_overview]).to be true
      end
    end

    context "when Ruby output has missing top-level keys" do
      let(:ruby_output) do
        output = python_output.dup
        output.delete("propertyMap")
        output
      end

      it "reports structure difference" do
        report = described_class.compare_outputs(
          python_output: python_output,
          ruby_output: ruby_output
        )

        expect(report.compatible?).to be false
        structure_diff = report.differences.find { |d| d[:category] == :structure }
        expect(structure_diff[:details][:missing]).to include("propertyMap")
      end
    end

    context "when cluster levels differ" do
      let(:ruby_output) do
        output = python_output.dup
        output["clusters"] = [
          { "level" => 0, "id" => "0", "label" => "All", "takeaway" => "", "value" => 10, "parent" => "" },
          { "level" => 1, "id" => "1_0", "label" => "Group A", "takeaway" => "Desc", "value" => 5, "parent" => "0" }
          # Missing level 2
        ]
        output
      end

      it "reports cluster level difference" do
        report = described_class.compare_outputs(
          python_output: python_output,
          ruby_output: ruby_output
        )

        expect(report.compatible?).to be false
        cluster_diff = report.differences.find { |d| d[:category] == :clusters }
        expect(cluster_diff[:message]).to include("hierarchy levels")
      end
    end

    context "when overview presence differs" do
      let(:ruby_output) do
        output = python_output.dup
        output["overview"] = ""
        output
      end

      it "reports overview difference" do
        report = described_class.compare_outputs(
          python_output: python_output,
          ruby_output: ruby_output
        )

        expect(report.compatible?).to be false
        overview_diff = report.differences.find { |d| d[:category] == :overview }
        expect(overview_diff).not_to be_nil
      end
    end
  end

  describe "ComparisonReport" do
    let(:report) { Broadlistening::Compatibility::ComparisonReport.new }

    describe "#summary" do
      it "generates human-readable summary" do
        report.instance_variable_set(:@python_stats, { argument_count: 100 })
        report.instance_variable_set(:@ruby_stats, { argument_count: 100 })

        summary = report.summary

        expect(summary).to include("Compatibility Report")
        expect(summary).to include("COMPATIBLE")
      end

      it "includes differences when incompatible" do
        report.add_difference(:structure, "Test difference", test: "value")

        summary = report.summary

        expect(summary).to include("INCOMPATIBLE")
        expect(summary).to include("Test difference")
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        report.add_difference(:test, "Test message")

        hash = report.to_h

        expect(hash[:compatible]).to be false
        expect(hash[:differences].size).to eq(1)
      end
    end
  end

  describe "REQUIRED constants" do
    it "defines required top-level keys" do
      expect(described_class::REQUIRED_TOP_LEVEL_KEYS).to include(
        "arguments", "clusters", "overview", "config"
      )
    end

    it "defines required argument keys" do
      expect(described_class::REQUIRED_ARGUMENT_KEYS).to include(
        "arg_id", "argument", "comment_id", "x", "y", "cluster_ids"
      )
    end

    it "defines required cluster keys" do
      expect(described_class::REQUIRED_CLUSTER_KEYS).to include(
        "level", "id", "label", "takeaway", "value", "parent"
      )
    end
  end

  describe ".schema" do
    it "returns the JSON Schema as a Hash" do
      schema = described_class.schema
      expect(schema).to be_a(Hash)
      expect(schema["$schema"]).to include("json-schema.org")
      expect(schema["title"]).to eq("Hierarchical Result")
    end
  end

  describe ".schema_path" do
    it "returns the path to the schema file" do
      path = described_class.schema_path
      expect(File.exist?(path)).to be true
      expect(path).to end_with("hierarchical_result.json")
    end
  end

  describe ".validate_with_schema" do
    let(:valid_output) do
      {
        "arguments" => [
          {
            "arg_id" => "A0_0",
            "argument" => "Test argument",
            "comment_id" => 0,
            "x" => 1.0,
            "y" => 2.0,
            "cluster_ids" => [ "0", "1_0" ]
          }
        ],
        "clusters" => [
          {
            "level" => 0,
            "id" => "0",
            "label" => "All",
            "takeaway" => "",
            "value" => 1,
            "parent" => ""
          }
        ],
        "comments" => {},
        "propertyMap" => {},
        "translations" => {},
        "overview" => "Test overview",
        "config" => {}
      }
    end

    it "returns empty array for valid output" do
      errors = described_class.validate_with_schema(valid_output)
      expect(errors).to be_empty
    end

    it "returns true for valid_schema? with valid output" do
      expect(described_class.valid_schema?(valid_output)).to be true
    end

    context "with invalid output" do
      let(:invalid_output) do
        { "arguments" => "not an array" }
      end

      it "returns validation errors" do
        errors = described_class.validate_with_schema(invalid_output)
        expect(errors).not_to be_empty
      end

      it "returns false for valid_schema?" do
        expect(described_class.valid_schema?(invalid_output)).to be false
      end
    end

    context "with missing required fields" do
      let(:incomplete_output) do
        {
          "arguments" => [],
          "clusters" => []
        }
      end

      it "returns errors for missing required fields" do
        errors = described_class.validate_with_schema(incomplete_output)
        expect(errors).not_to be_empty
      end
    end
  end
end
