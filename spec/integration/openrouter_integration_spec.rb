# frozen_string_literal: true

require "integration_helper"

RSpec.describe "OpenRouter Provider Integration" do
  # API-dependent tests (require OPENROUTER_API_KEY)
  context "with API key", :integration do
    before do
      skip "OPENROUTER_API_KEY not set" unless ENV["OPENROUTER_API_KEY"]
    end

    let(:config) do
      Broadlistening::Config.new(
        api_key: ENV.fetch("OPENROUTER_API_KEY", nil),
        provider: :openrouter,
        model: "openai/gpt-oss-120b",
        embedding_model: "openai/text-embedding-3-small"
      )
    end

    let(:client) { Broadlistening::LlmClient.new(config) }

    describe "#chat" do
    it "returns a valid response" do
      result = client.chat(
        system: "You are a helpful assistant.",
        user: "Say 'Hello' in Japanese."
      )

      expect(result).to be_a(Broadlistening::LlmClient::ChatResult)
      expect(result.content).to be_a(String)
      expect(result.content).not_to be_empty
    end

    it "handles Japanese text correctly" do
      result = client.chat(
        system: "あなたは日本語のアシスタントです。",
        user: "「こんにちは」という挨拶について簡潔に説明してください。"
      )

      expect(result.content).to be_a(String)
      expect(result.content).not_to be_empty
      expect(result.content).to match(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
    end

    context "with JSON mode" do
      it "returns valid JSON" do
        result = client.chat(
          system: "You are a helpful assistant. Respond only with valid JSON, no other text. Keep responses short.",
          user: 'Return exactly this JSON: {"greeting": "hello"}',
          json_mode: true
        )

        expect(result.content).to be_a(String)
        parsed = JSON.parse(JsonExtractor.extract_json(result.content))
        expect(parsed).to be_a(Hash)
      end
    end

    context "with Structured Outputs (json_schema)" do
      it "generates labels using JSON schema enforcement" do
        system_prompt = <<~PROMPT
          あなたはKJ法が得意なデータ分析者です。
          与えられた意見グループに対して、適切なラベルと説明を付けてください。
        PROMPT

        opinions = <<~TEXT
          - 環境問題への対策が必要
          - 温暖化対策を急ぐべき
          - 再生可能エネルギーの普及を
        TEXT

        result = client.chat(
          system: system_prompt,
          user: opinions,
          json_schema: Broadlistening::JsonSchemas::LABELLING
        )

        parsed = JSON.parse(JsonExtractor.extract_json(result.content))

        expect(parsed).to have_key("label")
        expect(parsed).to have_key("description")
        expect(parsed["label"]).to be_a(String)
        expect(parsed["label"]).not_to be_empty
      end

      it "extracts opinions using EXTRACTION schema" do
        system_prompt = config.prompts[:extraction]
        comment = "環境問題への対策が必要だと思います。また、公共交通機関の充実も望みます。"

        result = client.chat(
          system: system_prompt,
          user: comment,
          json_schema: Broadlistening::JsonSchemas::EXTRACTION
        )

        parsed = JSON.parse(JsonExtractor.extract_json(result.content))

        expect(parsed).to have_key("extractedOpinionList")
        expect(parsed["extractedOpinionList"]).to be_an(Array)
        expect(parsed["extractedOpinionList"]).not_to be_empty
      end
    end
  end

    describe "#embed" do
      it "returns valid embeddings for a single text" do
        embeddings = client.embed("テストテキスト")

        expect(embeddings).to be_an(Array)
        expect(embeddings.length).to eq(1)
        expect(embeddings.first).to be_an(Array)
        # OpenAI text-embedding-3-small has 1536 dimensions
        expect(embeddings.first.length).to eq(1536)
        expect(embeddings.first).to all(be_a(Numeric))
      end

      it "returns valid embeddings for multiple texts" do
        texts = [
          "環境問題への対策が必要",
          "公共交通機関の充実を希望"
        ]

        embeddings = client.embed(texts)

        expect(embeddings).to be_an(Array)
        expect(embeddings.length).to eq(2)
        embeddings.each do |embedding|
          expect(embedding).to be_an(Array)
          expect(embedding.length).to eq(1536)
        end
      end
    end
  end
end
