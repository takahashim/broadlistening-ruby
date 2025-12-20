# frozen_string_literal: true

require "tempfile"

RSpec.describe Broadlistening::Cli::Parser do
  let(:config_file) do
    file = Tempfile.new([ "test_config", ".json" ])
    file.write('{"input": "test.csv", "question": "test"}')
    file.close
    file
  end

  after do
    config_file.unlink
  end

  describe ".parse" do
    it "parses config path as first argument" do
      options = described_class.parse([ config_file.path ])

      expect(options.config_path).to eq(config_file.path)
    end

    it "parses -f/--force option" do
      options = described_class.parse([ config_file.path, "-f" ])

      expect(options.force).to be true
    end

    it "parses --force long option" do
      options = described_class.parse([ config_file.path, "--force" ])

      expect(options.force).to be true
    end

    it "parses -o/--only option" do
      options = described_class.parse([ config_file.path, "-o", "extraction" ])

      expect(options.only).to eq(:extraction)
    end

    it "parses --only long option" do
      options = described_class.parse([ config_file.path, "--only", "embedding" ])

      expect(options.only).to eq(:embedding)
    end

    it "parses --skip-interaction option" do
      options = described_class.parse([ config_file.path, "--skip-interaction" ])

      expect(options.skip_interaction).to be true
    end

    it "parses --from option" do
      options = described_class.parse([ config_file.path, "--from", "embedding" ])

      expect(options.from_step).to eq(:embedding)
    end

    it "parses --input-dir option" do
      options = described_class.parse([ config_file.path, "--input-dir", "/path/to/input" ])

      expect(options.input_dir).to eq("/path/to/input")
    end

    it "exits with help message on -h" do
      expect { described_class.parse([ "-h" ]) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    it "exits with version on -v" do
      expect { described_class.parse([ "-v" ]) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    it "returns an Options instance" do
      options = described_class.parse([ config_file.path ])

      expect(options).to be_a(Broadlistening::Cli::Options)
    end

    it "sets default values for unspecified options" do
      options = described_class.parse([ config_file.path ])

      expect(options.force).to be false
      expect(options.only).to be_nil
      expect(options.skip_interaction).to be false
      expect(options.from_step).to be_nil
      expect(options.input_dir).to be_nil
    end
  end
end
