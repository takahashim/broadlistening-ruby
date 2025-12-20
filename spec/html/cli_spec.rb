# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Broadlistening::Html::Cli do
  let(:fixture_path) { "spec/fixtures/hierarchical_result.json" }

  describe "#run" do
    it "generates HTML file" do
      Dir.mktmpdir do |tmpdir|
        output_path = File.join(tmpdir, "test_output.html")
        cli = described_class.new([ fixture_path, output_path ])

        cli.run

        expect(File.exist?(output_path)).to be true
        content = File.read(output_path)
        expect(content).to include("<!DOCTYPE html>")
      end
    end

    it "uses custom title when specified" do
      Dir.mktmpdir do |tmpdir|
        output_path = File.join(tmpdir, "test_output.html")
        cli = described_class.new([ fixture_path, output_path, "--title", "Custom Title" ])

        cli.run

        content = File.read(output_path)
        expect(content).to include("<title>Custom Title</title>")
      end
    end

    it "exits with error when input is missing" do
      cli = described_class.new([])

      expect { cli.run }.to raise_error(SystemExit)
    end

    it "exits with error for invalid JSON" do
      Tempfile.create([ "invalid", ".json" ]) do |f|
        f.write("not valid json")
        f.flush

        cli = described_class.new([ f.path, "output.html" ])

        expect { cli.run }.to raise_error(SystemExit)
      end
    end
  end
end
