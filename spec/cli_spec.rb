# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Broadlistening::CLI do
  let(:input_file) do
    file = Tempfile.new([ "input", ".csv" ])
    file.write("id,body\n1,テスト意見です\n2,別の意見です\n")
    file.close
    file
  end

  let(:config_file) do
    file = Tempfile.new([ "test_config", ".json" ])
    file.write({
      input: input_file.path,
      question: "テストの質問です",
      model: "gpt-4o-mini",
      api_key: "test-api-key",
      cluster_nums: [ 2, 5 ]
    }.to_json)
    file.close
    file
  end

  let(:expected_output_dir) { Broadlistening::CLI::PIPELINE_DIR / "test_config" }

  after do
    FileUtils.rm_rf(expected_output_dir) if expected_output_dir.exist?
    input_file.unlink
    config_file.unlink
  end

  describe "#parse_options" do
    it "parses config path as first argument" do
      cli = described_class.new([ config_file.path ])
      cli.send(:parse_options)

      expect(cli.instance_variable_get(:@config_path)).to eq(config_file.path)
    end

    it "parses -f/--force option" do
      cli = described_class.new([ config_file.path, "-f" ])
      cli.send(:parse_options)

      expect(cli.options[:force]).to be true
    end

    it "parses --force long option" do
      cli = described_class.new([ config_file.path, "--force" ])
      cli.send(:parse_options)

      expect(cli.options[:force]).to be true
    end

    it "parses -o/--only option" do
      cli = described_class.new([ config_file.path, "-o", "extraction" ])
      cli.send(:parse_options)

      expect(cli.options[:only]).to eq(:extraction)
    end

    it "parses --only long option" do
      cli = described_class.new([ config_file.path, "--only", "embedding" ])
      cli.send(:parse_options)

      expect(cli.options[:only]).to eq(:embedding)
    end

    it "parses --skip-interaction option" do
      cli = described_class.new([ config_file.path, "--skip-interaction" ])
      cli.send(:parse_options)

      expect(cli.options[:skip_interaction]).to be true
    end

    it "exits with help message on -h" do
      cli = described_class.new([ "-h" ])

      expect { cli.send(:parse_options) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    it "exits with version on -v" do
      cli = described_class.new([ "-v" ])

      expect { cli.send(:parse_options) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end
  end

  describe "#validate_config_path" do
    it "exits with error when config path is missing" do
      cli = described_class.new([])
      cli.send(:parse_options)

      expect { cli.send(:validate_config_path) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end

    it "exits with error when config file does not exist" do
      cli = described_class.new([ "/nonexistent/config.json" ])
      cli.send(:parse_options)

      expect { cli.send(:validate_config_path) }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end

    it "passes when config file exists" do
      cli = described_class.new([ config_file.path ])
      cli.send(:parse_options)

      expect { cli.send(:validate_config_path) }.not_to raise_error
    end
  end

  describe "#load_config" do
    it "loads JSON config file and returns Config object" do
      cli = described_class.new([ config_file.path ])
      cli.send(:parse_options)

      config = cli.send(:load_config)

      expect(config).to be_a(Broadlistening::Config)
      expect(config.input).to eq(input_file.path)
      expect(config.question).to eq("テストの質問です")
      expect(config.model).to eq("gpt-4o-mini")
    end

    it "raises error for invalid JSON" do
      invalid_file = Tempfile.new([ "invalid", ".json" ])
      invalid_file.write("not valid json")
      invalid_file.close

      cli = described_class.new([ invalid_file.path ])
      cli.send(:parse_options)

      expect { cli.send(:load_config) }.to raise_error(Broadlistening::ConfigurationError, /Invalid JSON/)

      invalid_file.unlink
    end
  end

  describe "#validate_config" do
    let(:cli) { described_class.new([ config_file.path ]) }

    before do
      cli.send(:parse_options)
    end

    it "raises error when input is missing" do
      config = Broadlistening::Config.new(
        api_key: "test",
        question: "test question"
      )

      expect { cli.send(:validate_config, config) }.to raise_error(
        Broadlistening::ConfigurationError, /Missing required field 'input'/
      )
    end

    it "raises error when question is missing" do
      config = Broadlistening::Config.new(
        api_key: "test",
        input: input_file.path
      )

      expect { cli.send(:validate_config, config) }.to raise_error(
        Broadlistening::ConfigurationError, /Missing required field 'question'/
      )
    end

    it "raises error when input file does not exist" do
      config = Broadlistening::Config.new(
        api_key: "test",
        input: "/nonexistent/file.csv",
        question: "test question"
      )

      expect { cli.send(:validate_config, config) }.to raise_error(
        Broadlistening::ConfigurationError, /Input file not found/
      )
    end

    it "passes when all required fields are present" do
      config = cli.send(:load_config)

      expect { cli.send(:validate_config, config) }.not_to raise_error
    end
  end

  describe "#determine_output_dir" do
    it "generates output directory from config filename" do
      cli = described_class.new([ config_file.path ])
      cli.send(:parse_options)

      output_dir = cli.send(:determine_output_dir)

      expect(output_dir.to_s).to include("test_config")
      expect(output_dir.parent).to eq(Broadlistening::CLI::PIPELINE_DIR)
    end

    it "strips extension from config filename" do
      cli = described_class.new([ "/path/to/my_report.json" ])
      cli.send(:parse_options)

      output_dir = cli.send(:determine_output_dir)

      expect(output_dir.basename.to_s).to eq("my_report")
    end
  end

  describe "#load_comments" do
    let(:cli) { described_class.new([ config_file.path ]) }

    it "loads CSV file" do
      comments = cli.send(:load_comments, input_file.path)

      expect(comments).to be_an(Array)
      expect(comments.size).to eq(2)
    end

    it "loads JSON file" do
      json_input = Tempfile.new([ "input", ".json" ])
      json_input.write([ { id: "1", body: "テスト" } ].to_json)
      json_input.close

      comments = cli.send(:load_comments, json_input.path)

      expect(comments).to be_an(Array)
      expect(comments.size).to eq(1)
      expect(comments.first[:id]).to eq("1")

      json_input.unlink
    end

    it "raises error for unsupported format" do
      expect { cli.send(:load_comments, "/path/to/file.txt") }.to raise_error(
        Broadlistening::ConfigurationError, /Unsupported input format/
      )
    end
  end

  describe "#confirm_execution" do
    let(:cli) { described_class.new([ config_file.path ]) }

    it "returns true when user presses enter" do
      allow($stdin).to receive(:gets).and_return("\n")

      result = cli.send(:confirm_execution)

      expect(result).to be true
    end
  end

  describe "#run" do
    it "runs pipeline when all validations pass" do
      cli = described_class.new([ config_file.path, "--skip-interaction" ])

      # Mock the pipeline execution
      mock_pipeline = instance_double(Broadlistening::Pipeline)
      allow(Broadlistening::Pipeline).to receive(:new).and_return(mock_pipeline)
      allow(mock_pipeline).to receive(:run).and_return({ result: {} })

      expect { cli.run }.not_to raise_error
      expect(mock_pipeline).to have_received(:run)
    end

    it "creates output directory matching config filename" do
      cli = described_class.new([ config_file.path, "--skip-interaction" ])

      mock_pipeline = instance_double(Broadlistening::Pipeline)
      allow(Broadlistening::Pipeline).to receive(:new).and_return(mock_pipeline)
      allow(mock_pipeline).to receive(:run).and_return({ result: {} })

      cli.run

      # Tempfile generates unique names, so check that output dir was created with config basename
      config_basename = File.basename(config_file.path, ".*")
      actual_output_dir = Broadlistening::CLI::PIPELINE_DIR / config_basename
      expect(actual_output_dir).to exist

      # Cleanup
      FileUtils.rm_rf(actual_output_dir)
    end

    it "exits with error on Broadlistening::Error" do
      cli = described_class.new([ config_file.path, "--skip-interaction" ])

      allow(Broadlistening::Pipeline).to receive(:new).and_raise(
        Broadlistening::ConfigurationError, "Test error"
      )

      expect { cli.run }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end

    it "exits with error when question is missing from config" do
      no_question_file = Tempfile.new([ "no_question", ".json" ])
      no_question_file.write({
        input: input_file.path,
        model: "gpt-4o-mini",
        api_key: "test-api-key"
      }.to_json)
      no_question_file.close

      cli = described_class.new([ no_question_file.path, "--skip-interaction" ])

      expect { cli.run }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end

      no_question_file.unlink
    end
  end

  describe "Python CLI compatibility" do
    it "accepts same options as Python version" do
      # -f, --force
      cli_f = described_class.new([ config_file.path, "-f" ])
      cli_f.send(:parse_options)
      expect(cli_f.options[:force]).to be true

      # -o, --only
      cli_o = described_class.new([ config_file.path, "-o", "extraction" ])
      cli_o.send(:parse_options)
      expect(cli_o.options[:only]).to eq(:extraction)

      # --skip-interaction
      cli_skip = described_class.new([ config_file.path, "--skip-interaction" ])
      cli_skip.send(:parse_options)
      expect(cli_skip.options[:skip_interaction]).to be true
    end

    it "validates same required fields as Python version" do
      # Python requires: input, question
      cli = described_class.new([ config_file.path ])
      cli.send(:parse_options)
      config = cli.send(:load_config)

      expect(config.input).not_to be_nil
      expect(config.question).not_to be_nil
    end
  end
end
