# frozen_string_literal: true

require "spec_helper"

RSpec.describe Broadlistening::Html::Cli::Options do
  let(:fixture_path) { "spec/fixtures/hierarchical_result.json" }

  describe "#initialize" do
    it "has default output_path" do
      options = described_class.new

      expect(options.output_path).to eq("report.html")
    end

    it "has nil defaults for optional fields" do
      options = described_class.new

      expect(options.input_path).to be_nil
      expect(options.template).to be_nil
      expect(options.title).to be_nil
    end
  end

  describe "#validate!" do
    it "raises error when input_path is nil" do
      options = described_class.new

      expect { options.validate! }.to raise_error(
        Broadlistening::ConfigurationError, /INPUT_JSON is required/
      )
    end

    it "raises error when input file does not exist" do
      options = described_class.new
      options.input_path = "/nonexistent/file.json"

      expect { options.validate! }.to raise_error(
        Broadlistening::ConfigurationError, /Input file not found/
      )
    end

    it "raises error when template file does not exist" do
      options = described_class.new
      options.input_path = fixture_path
      options.template = "/nonexistent/template.erb"

      expect { options.validate! }.to raise_error(
        Broadlistening::ConfigurationError, /Template file not found/
      )
    end

    it "passes when input file exists" do
      options = described_class.new
      options.input_path = fixture_path

      expect { options.validate! }.not_to raise_error
    end
  end

  describe "#to_h" do
    it "returns hash with template and title" do
      options = described_class.new
      options.template = "custom.erb"
      options.title = "My Report"

      expect(options.to_h).to eq({ template: "custom.erb", title: "My Report" })
    end

    it "excludes nil values" do
      options = described_class.new
      options.title = "My Report"

      expect(options.to_h).to eq({ title: "My Report" })
    end

    it "returns empty hash when no options set" do
      options = described_class.new

      expect(options.to_h).to eq({})
    end
  end
end
