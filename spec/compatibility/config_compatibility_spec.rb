# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe "Config Compatibility" do
  # Tests to verify Config format matches Python's config.json
  # Python: hierarchical_utils.py validate_config, initialization
  # Ruby: Config class

  # Mock ENV for all tests
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return("test-api-key")
    allow(ENV).to receive(:fetch).with("AZURE_OPENAI_API_KEY", nil).and_return("test-azure-key")
    allow(ENV).to receive(:fetch).with("LOCAL_LLM_ADDRESS", "localhost:11434").and_return("localhost:11434")
    allow(ENV).to receive(:fetch).with("AZURE_API_VERSION", "2024-02-15-preview").and_return("2024-02-15-preview")
  end

  describe "Reading Python-format config files" do
    # Python config.json structure used by hierarchical_main.py

    describe "minimal required config" do
      let(:python_config) do
        {
          "input" => "test_data",
          "question" => "What do you think about this topic?",
          "model" => "gpt-4o-mini"
        }
      end

      let(:config_file) do
        file = Tempfile.new([ "config", ".json" ])
        file.write(JSON.generate(python_config))
        file.close
        file
      end

      after { config_file.unlink }

      it "reads input field" do
        # Note: Ruby Config uses 'input' for the input file name
        config = Broadlistening::Config.from_file(config_file.path)
        expect(config.input).to eq("test_data")
      end

      it "reads question field" do
        config = Broadlistening::Config.from_file(config_file.path)
        expect(config.question).to eq("What do you think about this topic?")
      end

      it "reads model field" do
        config = Broadlistening::Config.from_file(config_file.path)
        expect(config.model).to eq("gpt-4o-mini")
      end
    end

    describe "full Python config with all fields" do
      let(:python_config) do
        {
          "input" => "survey_data",
          "question" => "What are your thoughts on the new policy?",
          "model" => "gpt-4o",
          "name" => "Policy Survey Analysis",
          "intro" => "This analysis covers public opinions on the new policy.",
          "is_pubcom" => true,
          "provider" => "openai",
          "local_llm_address" => "localhost:11434",
          "enable_source_link" => true,
          "extraction" => {
            "limit" => 500,
            "workers" => 5
          },
          "hierarchical_clustering" => {
            "cluster_nums" => [ 3, 10, 30 ]
          },
          "hierarchical_aggregation" => {
            "hidden_properties" => {
              "source" => [ "anonymous" ]
            }
          }
        }
      end

      let(:config_file) do
        file = Tempfile.new([ "config", ".json" ])
        file.write(JSON.generate(python_config))
        file.close
        file
      end

      after { config_file.unlink }

      let(:config) { Broadlistening::Config.from_file(config_file.path) }

      it "reads name field" do
        expect(config.name).to eq("Policy Survey Analysis")
      end

      it "reads intro field" do
        expect(config.intro).to eq("This analysis covers public opinions on the new policy.")
      end

      it "reads is_pubcom field" do
        expect(config.is_pubcom).to be true
      end

      it "reads provider field" do
        expect(config.provider).to eq(:openai)
      end

      it "reads local_llm_address field" do
        expect(config.local_llm_address).to eq("localhost:11434")
      end

      it "reads enable_source_link field" do
        expect(config.enable_source_link).to be true
      end

      it "reads extraction.limit" do
        expect(config.limit).to eq(500)
      end

      it "reads extraction.workers" do
        expect(config.workers).to eq(5)
      end

      it "reads hierarchical_clustering.cluster_nums" do
        expect(config.cluster_nums).to eq([ 3, 10, 30 ])
      end

      it "reads hidden_properties" do
        # Ruby uses symbol keys internally (from JSON.parse with symbolize_names)
        expect(config.hidden_properties).to eq({ source: [ "anonymous" ] })
      end
    end

    describe "Azure provider config" do
      let(:azure_config) do
        {
          "input" => "data",
          "question" => "Question",
          "provider" => "azure",
          "model" => "gpt-4o-mini",
          "api_base_url" => "https://my-resource.openai.azure.com/"
        }
      end

      let(:config_file) do
        file = Tempfile.new([ "config", ".json" ])
        file.write(JSON.generate(azure_config))
        file.close
        file
      end

      after { config_file.unlink }

      it "reads azure provider" do
        config = Broadlistening::Config.from_file(config_file.path)
        expect(config.provider).to eq(:azure)
      end

      it "reads api_base_url" do
        config = Broadlistening::Config.from_file(config_file.path)
        expect(config.api_base_url).to eq("https://my-resource.openai.azure.com/")
      end
    end

    describe "local LLM provider config" do
      let(:local_config) do
        {
          "input" => "data",
          "question" => "Question",
          "provider" => "local",
          "model" => "elyza:jp8b",
          "local_llm_address" => "localhost:11434"
        }
      end

      let(:config_file) do
        file = Tempfile.new([ "config", ".json" ])
        file.write(JSON.generate(local_config))
        file.close
        file
      end

      after { config_file.unlink }

      it "reads local provider" do
        config = Broadlistening::Config.from_file(config_file.path)
        expect(config.provider).to eq(:local)
      end

      it "reads local_llm_address" do
        config = Broadlistening::Config.from_file(config_file.path)
        expect(config.local_llm_address).to eq("localhost:11434")
      end
    end
  end

  describe "Default values" do
    # Python sets default values for missing fields

    let(:minimal_config) do
      {
        "input" => "data",
        "question" => "Question"
      }
    end

    let(:config_file) do
      file = Tempfile.new([ "config", ".json" ])
      file.write(JSON.generate(minimal_config))
      file.close
      file
    end

    after { config_file.unlink }

    let(:config) { Broadlistening::Config.from_file(config_file.path) }

    it "defaults model to gpt-4o-mini (matching Python)" do
      # Python: if "model" not in config: config["model"] = "gpt-4o-mini"
      expect(config.model).to eq("gpt-4o-mini")
    end

    it "defaults provider to openai" do
      expect(config.provider).to eq(:openai)
    end

    it "defaults cluster_nums to [5, 15]" do
      expect(config.cluster_nums).to eq([ 5, 15 ])
    end

    it "defaults workers to 10" do
      expect(config.workers).to eq(10)
    end

    it "defaults limit to 1000" do
      expect(config.limit).to eq(1000)
    end

    it "defaults enable_source_link to false" do
      expect(config.enable_source_link).to be false
    end

    it "defaults is_pubcom to false" do
      expect(config.is_pubcom).to be false
    end
  end

  describe "Prompt configuration" do
    # Python: prompts can be set per-step or via prompt_file

    describe "custom prompts" do
      let(:config_with_prompts) do
        {
          "input" => "data",
          "question" => "Question",
          "prompts" => {
            "extraction" => "Custom extraction prompt",
            "initial_labelling" => "Custom labelling prompt"
          }
        }
      end

      let(:config_file) do
        file = Tempfile.new([ "config", ".json" ])
        file.write(JSON.generate(config_with_prompts))
        file.close
        file
      end

      after { config_file.unlink }

      let(:config) { Broadlistening::Config.from_file(config_file.path) }

      it "reads custom extraction prompt" do
        expect(config.prompts[:extraction]).to eq("Custom extraction prompt")
      end

      it "reads custom initial_labelling prompt" do
        expect(config.prompts[:initial_labelling]).to eq("Custom labelling prompt")
      end

      it "uses default for unspecified prompts" do
        expect(config.prompts[:overview]).to be_a(String)
        expect(config.prompts[:overview]).not_to be_empty
      end
    end
  end

  describe "Writing Ruby config (Python-compatible format)" do
    let(:config) do
      Broadlistening::Config.new(
        api_key: "test-key",
        model: "gpt-4o",
        cluster_nums: [ 3, 10, 30 ],
        limit: 500,
        workers: 5,
        is_pubcom: true,
        enable_source_link: true,
        input: "survey_data",
        question: "What do you think?",
        name: "Survey Analysis",
        intro: "Analysis intro text"
      )
    end

    let(:config_file) { Tempfile.new([ "config", ".json" ]) }

    after { config_file.unlink }

    before do
      config.save_to_file(config_file.path)
    end

    let(:saved_config) { JSON.parse(File.read(config_file.path)) }

    it "writes model" do
      expect(saved_config["model"]).to eq("gpt-4o")
    end

    it "writes cluster_nums" do
      expect(saved_config["cluster_nums"]).to eq([ 3, 10, 30 ])
    end

    it "writes limit" do
      expect(saved_config["limit"]).to eq(500)
    end

    it "writes workers" do
      expect(saved_config["workers"]).to eq(5)
    end

    it "writes is_pubcom" do
      expect(saved_config["is_pubcom"]).to be true
    end

    it "writes enable_source_link" do
      expect(saved_config["enable_source_link"]).to be true
    end

    it "writes name" do
      expect(saved_config["name"]).to eq("Survey Analysis")
    end

    it "writes intro" do
      expect(saved_config["intro"]).to eq("Analysis intro text")
    end

    it "writes prompts" do
      expect(saved_config["prompts"]).to be_a(Hash)
      expect(saved_config["prompts"]["extraction"]).to be_a(String)
    end
  end

  describe "Round-trip compatibility" do
    let(:original_config) do
      {
        "input" => "test_data",
        "question" => "What are your thoughts?",
        "model" => "gpt-4o-mini",
        "name" => "Test Analysis",
        "intro" => "Introduction text",
        "is_pubcom" => true,
        "enable_source_link" => true,
        "cluster_nums" => [ 5, 15 ],
        "limit" => 1000,
        "workers" => 10
      }
    end

    let(:config_file) { Tempfile.new([ "config", ".json" ]) }
    let(:output_file) { Tempfile.new([ "config_output", ".json" ]) }

    after do
      config_file.unlink
      output_file.unlink
    end

    it "preserves essential fields through read/write cycle" do
      # Write original
      File.write(config_file.path, JSON.generate(original_config))

      # Read with Ruby
      config = Broadlistening::Config.from_file(config_file.path)

      # Write with Ruby
      config.save_to_file(output_file.path)

      # Read back
      saved = JSON.parse(File.read(output_file.path))

      # Essential fields should be preserved
      expect(saved["model"]).to eq(original_config["model"])
      expect(saved["cluster_nums"]).to eq(original_config["cluster_nums"])
      expect(saved["limit"]).to eq(original_config["limit"])
      expect(saved["is_pubcom"]).to eq(original_config["is_pubcom"])
      expect(saved["enable_source_link"]).to eq(original_config["enable_source_link"])
    end
  end

  describe "property_names extraction" do
    # Python uses hidden_properties to determine which properties to track

    let(:config_with_hidden_properties) do
      Broadlistening::Config.new(
        api_key: "test-key",
        model: "gpt-4o-mini",
        cluster_nums: [ 5, 15 ],
        hidden_properties: {
          "source" => [ "hidden_value" ],
          "category" => []
        }
      )
    end

    it "extracts property_names from hidden_properties keys" do
      expect(config_with_hidden_properties.property_names).to match_array(%w[source category])
    end

    it "returns empty array when no hidden_properties" do
      config = Broadlistening::Config.new(
        api_key: "test-key",
        model: "gpt-4o-mini",
        cluster_nums: [ 5, 15 ]
      )
      expect(config.property_names).to eq([])
    end
  end
end
