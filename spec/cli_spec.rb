# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Broadlistening::Cli do
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

  let(:expected_output_dir) { Broadlistening::Cli::PIPELINE_DIR / "test_config" }

  after do
    FileUtils.rm_rf(expected_output_dir) if expected_output_dir.exist?
    input_file.unlink
    config_file.unlink
  end

  describe "#options" do
    it "returns Options instance after parsing" do
      cli = described_class.new([ config_file.path, "--skip-interaction" ])

      # Trigger parsing by calling a method that uses options
      mock_pipeline = instance_double(Broadlistening::Pipeline)
      allow(Broadlistening::Pipeline).to receive(:new).and_return(mock_pipeline)
      allow(mock_pipeline).to receive(:run).and_return({ result: {} })

      cli.run

      expect(cli.options).to be_a(Broadlistening::Cli::Options)
      expect(cli.options.config_path).to eq(config_file.path)
      expect(cli.options.skip_interaction).to be true
    end
  end

  describe "#determine_output_dir" do
    it "generates output directory from config filename" do
      cli = described_class.new([ config_file.path, "--skip-interaction" ])

      mock_pipeline = instance_double(Broadlistening::Pipeline)
      allow(Broadlistening::Pipeline).to receive(:new).and_return(mock_pipeline)
      allow(mock_pipeline).to receive(:run).and_return({ result: {} })

      cli.run

      output_dir = cli.send(:determine_output_dir)

      expect(output_dir.to_s).to include("test_config")
      expect(output_dir.parent).to eq(Broadlistening::Cli::PIPELINE_DIR)
    end

    it "strips extension from config filename" do
      cli = described_class.new([ config_file.path, "--skip-interaction" ])

      mock_pipeline = instance_double(Broadlistening::Pipeline)
      allow(Broadlistening::Pipeline).to receive(:new).and_return(mock_pipeline)
      allow(mock_pipeline).to receive(:run).and_return({ result: {} })

      cli.run

      output_dir = cli.send(:determine_output_dir)
      expect(output_dir.basename.to_s).to match(/^test_config/)
    end
  end

  describe "#load_comments" do
    let(:cli) do
      cli = described_class.new([ config_file.path, "--skip-interaction" ])
      mock_pipeline = instance_double(Broadlistening::Pipeline)
      allow(Broadlistening::Pipeline).to receive(:new).and_return(mock_pipeline)
      allow(mock_pipeline).to receive(:run).and_return({ result: {} })
      cli.run
      cli
    end

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
    it "returns true when user presses enter" do
      cli = described_class.new([ config_file.path ])
      allow($stdin).to receive(:gets).and_return("\n")

      result = cli.send(:confirm_execution)

      expect(result).to be true
    end
  end

  describe "#run" do
    it "runs pipeline when all validations pass" do
      cli = described_class.new([ config_file.path, "--skip-interaction" ])

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

      config_basename = File.basename(config_file.path, ".*")
      actual_output_dir = Broadlistening::Cli::PIPELINE_DIR / config_basename
      expect(actual_output_dir).to exist

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

    it "passes options to pipeline" do
      cli = described_class.new([ config_file.path, "--skip-interaction", "-f", "-o", "extraction" ])

      mock_pipeline = instance_double(Broadlistening::Pipeline)
      allow(Broadlistening::Pipeline).to receive(:new).and_return(mock_pipeline)
      allow(mock_pipeline).to receive(:run).and_return({ result: {} })

      cli.run

      expect(mock_pipeline).to have_received(:run).with(
        anything,
        hash_including(
          force: true,
          only: :extraction
        )
      )
    end
  end

  describe "Python CLI compatibility" do
    it "accepts same options as Python version" do
      # -f, --force
      cli_f = described_class.new([ config_file.path, "-f", "--skip-interaction" ])
      mock_pipeline = instance_double(Broadlistening::Pipeline)
      allow(Broadlistening::Pipeline).to receive(:new).and_return(mock_pipeline)
      allow(mock_pipeline).to receive(:run).and_return({ result: {} })
      cli_f.run
      expect(cli_f.options.force).to be true

      # -o, --only
      cli_o = described_class.new([ config_file.path, "-o", "extraction", "--skip-interaction" ])
      cli_o.run
      expect(cli_o.options.only).to eq(:extraction)

      # --skip-interaction
      cli_skip = described_class.new([ config_file.path, "--skip-interaction" ])
      cli_skip.run
      expect(cli_skip.options.skip_interaction).to be true
    end

    it "validates same required fields as Python version" do
      cli = described_class.new([ config_file.path, "--skip-interaction" ])
      mock_pipeline = instance_double(Broadlistening::Pipeline)
      allow(Broadlistening::Pipeline).to receive(:new).and_return(mock_pipeline)
      allow(mock_pipeline).to receive(:run).and_return({ result: {} })
      cli.run

      config = cli.send(:load_config)
      expect(config.input).not_to be_nil
      expect(config.question).not_to be_nil
    end
  end
end
