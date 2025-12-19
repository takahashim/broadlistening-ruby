# frozen_string_literal: true

require "integration_helper"

RSpec.describe "Gemini Provider Integration" do
  before do
    skip "GEMINI_API_KEY not set" unless ENV["GEMINI_API_KEY"]
  end

  let(:config) do
    Broadlistening::Config.new(
      api_key: ENV.fetch("GEMINI_API_KEY", nil),
      provider: :gemini,
      model: "gemini-2.0-flash",
      embedding_model: "text-embedding-004"
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
      it "returns valid JSON with explicit JSON instruction" do
        result = client.chat(
          system: "You are a helpful assistant. Always respond in JSON format.",
          user: "Return a JSON object with a 'greeting' key containing 'hello'.",
          json_mode: true
        )

        expect(result.content).to be_a(String)
        parsed = JSON.parse(result.content)
        expect(parsed).to be_a(Hash)
      end
    end
  end

  describe "#embed" do
    it "returns valid embeddings for a single text" do
      embeddings = client.embed("テストテキスト")

      expect(embeddings).to be_an(Array)
      expect(embeddings.length).to eq(1)
      expect(embeddings.first).to be_an(Array)
      # Gemini text-embedding-004 has 768 dimensions
      expect(embeddings.first.length).to eq(768)
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
        expect(embedding.length).to eq(768)
      end
    end

    it "returns different embeddings for semantically different texts" do
      # Use more distinct texts to ensure different embeddings
      embeddings = client.embed([
        "環境問題と地球温暖化対策について",
        "プログラミング言語Rubyの特徴"
      ])

      expect(embeddings[0]).not_to eq(embeddings[1])
    end
  end
end
