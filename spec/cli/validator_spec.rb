# frozen_string_literal: true

require "tempfile"

RSpec.describe Broadlistening::Cli::Validator do
  let(:input_file) do
    file = Tempfile.new([ "input", ".csv" ])
    file.write("id,body\n1,test\n")
    file.close
    file
  end

  let(:config_file) do
    file = Tempfile.new([ "test_config", ".json" ])
    file.write({
      input: input_file.path,
      question: "test question",
      model: "gpt-4o-mini",
      api_key: "test-api-key"
    }.to_json)
    file.close
    file
  end

  after do
    input_file.unlink
    config_file.unlink
  end

  describe ".validate!" do
    context "config path validation" do
      it "exits when config path is missing" do
        options = Broadlistening::Cli::Options.new

        expect { described_class.validate!(options) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "exits when config file does not exist" do
        options = Broadlistening::Cli::Options.new
        options.config_path = "/nonexistent/config.json"

        expect { described_class.validate!(options) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "passes when config file exists" do
        options = Broadlistening::Cli::Options.new
        options.config_path = config_file.path

        expect { described_class.validate!(options) }.not_to raise_error
      end
    end

    context "resume options validation" do
      it "passes when --from is used without --input-dir (uses output_dir)" do
        options = Broadlistening::Cli::Options.new
        options.config_path = config_file.path
        options.from_step = :embedding

        expect { described_class.validate!(options) }.not_to raise_error
      end

      it "exits when --input-dir is used without --from" do
        options = Broadlistening::Cli::Options.new
        options.config_path = config_file.path
        options.input_dir = "/path/to/input"

        expect { described_class.validate!(options) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "exits when --from and --only are used together" do
        options = Broadlistening::Cli::Options.new
        options.config_path = config_file.path
        options.from_step = :embedding
        options.input_dir = "/tmp"
        options.only = :clustering

        expect { described_class.validate!(options) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "passes when neither --from nor --input-dir is specified" do
        options = Broadlistening::Cli::Options.new
        options.config_path = config_file.path

        expect { described_class.validate!(options) }.not_to raise_error
      end
    end
  end

  describe ".validate_config!" do
    it "raises error when input is missing" do
      config = Broadlistening::Config.new(
        api_key: "test",
        question: "test question"
      )

      expect { described_class.validate_config!(config) }.to raise_error(
        Broadlistening::ConfigurationError, /Missing required field 'input'/
      )
    end

    it "raises error when question is missing" do
      config = Broadlistening::Config.new(
        api_key: "test",
        input: input_file.path
      )

      expect { described_class.validate_config!(config) }.to raise_error(
        Broadlistening::ConfigurationError, /Missing required field 'question'/
      )
    end

    it "raises error when input file does not exist" do
      config = Broadlistening::Config.new(
        api_key: "test",
        input: "/nonexistent/file.csv",
        question: "test question"
      )

      expect { described_class.validate_config!(config) }.to raise_error(
        Broadlistening::ConfigurationError, /Input file not found/
      )
    end

    it "passes when all required fields are present" do
      config = Broadlistening::Config.from_file(config_file.path)

      expect { described_class.validate_config!(config) }.not_to raise_error
    end
  end
end
