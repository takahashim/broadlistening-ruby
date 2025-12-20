# frozen_string_literal: true

require "spec_helper"

RSpec.describe Broadlistening::Html::Cli::Parser do
  let(:fixture_path) { "spec/fixtures/hierarchical_result.json" }

  describe ".parse" do
    it "parses input path as first argument" do
      options = described_class.parse([ fixture_path ])

      expect(options.input_path).to eq(fixture_path)
    end

    it "parses output path as second argument" do
      options = described_class.parse([ fixture_path, "output.html" ])

      expect(options.output_path).to eq("output.html")
    end

    it "uses default output path when not specified" do
      options = described_class.parse([ fixture_path ])

      expect(options.output_path).to eq("report.html")
    end

    it "parses -t/--template option" do
      options = described_class.parse([ fixture_path, "-t", "custom.erb" ])

      expect(options.template).to eq("custom.erb")
    end

    it "parses --title option" do
      options = described_class.parse([ fixture_path, "--title", "My Report" ])

      expect(options.title).to eq("My Report")
    end

    it "exits with help on -h" do
      expect { described_class.parse([ "-h" ]) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    it "exits with version on -v" do
      expect { described_class.parse([ "-v" ]) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end
  end
end
