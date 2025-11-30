# frozen_string_literal: true

RSpec.describe Broadlistening::Provider do
  describe ".supported?" do
    it "returns true for supported providers" do
      %w[openai azure gemini openrouter local].each do |name|
        expect(described_class.supported?(name)).to be true
      end
    end

    it "returns false for unsupported providers" do
      expect(described_class.supported?("unknown")).to be false
    end
  end

  describe ".supported_names" do
    it "returns list of supported provider names" do
      expect(described_class.supported_names).to eq(%w[openai azure gemini openrouter local])
    end
  end

  describe "#initialize" do
    it "creates provider for valid name" do
      provider = described_class.new("openai")
      expect(provider.name).to eq("openai")
    end

    it "raises error for unknown provider" do
      expect { described_class.new("unknown") }
        .to raise_error(Broadlistening::ConfigurationError, /Unknown provider/)
    end
  end

  describe "#api_key" do
    context "with openai provider" do
      it "returns API key from environment" do
        allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return("test-key")
        provider = described_class.new("openai")
        expect(provider.api_key).to eq("test-key")
      end
    end

    context "with local provider" do
      it "returns 'not-needed'" do
        provider = described_class.new("local")
        expect(provider.api_key).to eq("not-needed")
      end
    end
  end

  describe "#base_url" do
    context "with openai provider" do
      it "returns nil" do
        provider = described_class.new("openai")
        expect(provider.base_url).to be_nil
      end
    end

    context "with gemini provider" do
      it "returns Gemini API URL" do
        provider = described_class.new("gemini")
        expect(provider.base_url).to eq("https://generativelanguage.googleapis.com/v1beta/openai/")
      end
    end

    context "with openrouter provider" do
      it "returns OpenRouter API URL" do
        provider = described_class.new("openrouter")
        expect(provider.base_url).to eq("https://openrouter.ai/api/v1")
      end
    end

    context "with local provider" do
      it "returns local LLM URL with default address" do
        provider = described_class.new("local")
        expect(provider.base_url).to eq("http://localhost:11434/v1")
      end

      it "returns local LLM URL with custom address" do
        provider = described_class.new("local", local_llm_address: "192.168.1.100:8080")
        expect(provider.base_url).to eq("http://192.168.1.100:8080/v1")
      end
    end

    context "with azure provider" do
      it "returns URL from environment" do
        allow(ENV).to receive(:fetch).with("AZURE_OPENAI_URI", nil).and_return("https://my-resource.openai.azure.com")
        provider = described_class.new("azure")
        expect(provider.base_url).to eq("https://my-resource.openai.azure.com")
      end
    end
  end

  describe "#default_model" do
    it "returns gpt-4o-mini for openai" do
      provider = described_class.new("openai")
      expect(provider.default_model).to eq("gpt-4o-mini")
    end

    it "returns gemini-2.0-flash for gemini" do
      provider = described_class.new("gemini")
      expect(provider.default_model).to eq("gemini-2.0-flash")
    end
  end

  describe "#default_embedding_model" do
    it "returns text-embedding-3-small for openai" do
      provider = described_class.new("openai")
      expect(provider.default_embedding_model).to eq("text-embedding-3-small")
    end

    it "returns text-embedding-004 for gemini" do
      provider = described_class.new("gemini")
      expect(provider.default_embedding_model).to eq("text-embedding-004")
    end
  end

  describe "#requires_api_key?" do
    it "returns true for openai" do
      provider = described_class.new("openai")
      expect(provider.requires_api_key?).to be true
    end

    it "returns false for local" do
      provider = described_class.new("local")
      expect(provider.requires_api_key?).to be false
    end
  end

  describe "#requires_base_url?" do
    it "returns true for azure" do
      provider = described_class.new("azure")
      expect(provider.requires_base_url?).to be true
    end

    it "returns false for openai" do
      provider = described_class.new("openai")
      expect(provider.requires_base_url?).to be false
    end
  end

  describe "#azure?" do
    it "returns true for azure" do
      provider = described_class.new("azure")
      expect(provider.azure?).to be true
    end

    it "returns false for openai" do
      provider = described_class.new("openai")
      expect(provider.azure?).to be false
    end
  end

  describe "#build_openai_client" do
    it "builds client for openai" do
      provider = described_class.new("openai")
      client = provider.build_openai_client(api_key: "test-key", base_url: nil)
      expect(client).to be_a(OpenAI::Client)
    end

    it "builds client with base_url for gemini" do
      provider = described_class.new("gemini")
      client = provider.build_openai_client(
        api_key: "test-key",
        base_url: "https://generativelanguage.googleapis.com/v1beta/openai/"
      )
      expect(client).to be_a(OpenAI::Client)
    end

    it "builds azure client with api_type and api_version" do
      provider = described_class.new("azure")
      client = provider.build_openai_client(
        api_key: "test-key",
        base_url: "https://my-resource.openai.azure.com",
        azure_api_version: "2024-02-15-preview"
      )
      expect(client).to be_a(OpenAI::Client)
    end
  end
end
