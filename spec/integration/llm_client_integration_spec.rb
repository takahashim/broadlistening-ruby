# frozen_string_literal: true

require "integration_helper"

RSpec.describe Broadlistening::LlmClient do
  before do
    skip "OPENAI_API_KEY not set" unless ENV["OPENAI_API_KEY"]
  end

  let(:config) do
    Broadlistening::Config.new(
      api_key: ENV.fetch("OPENAI_API_KEY", nil),
      provider: :openai,
      model: "gpt-4o-mini",
      embedding_model: "text-embedding-3-small"
    )
  end

  let(:client) { described_class.new(config) }

  describe "#chat" do
    it "returns a valid response" do
      result = client.chat(
        system: "You are a helpful assistant.",
        user: "Say 'Hello' in Japanese."
      )

      expect(result).to be_a(Broadlistening::LlmClient::ChatResult)
      expect(result.content).to be_a(String)
      expect(result.content).not_to be_empty
      expect(result.token_usage).to be_a(Broadlistening::TokenUsage)
      expect(result.token_usage.total).to be > 0
    end

    it "supports JSON mode" do
      result = client.chat(
        system: "Return a JSON object with a 'greeting' key containing a greeting message.",
        user: "Give me a greeting.",
        json_mode: true
      )

      expect(result.content).to be_a(String)
      expect { JSON.parse(result.content) }.not_to raise_error

      parsed = JSON.parse(result.content)
      expect(parsed).to have_key("greeting")
    end

    it "handles Japanese text correctly" do
      result = client.chat(
        system: "あなたは日本語のアシスタントです。",
        user: "「こんにちは」という挨拶について簡潔に説明してください。"
      )

      expect(result.content).to be_a(String)
      expect(result.content).not_to be_empty
      # Response should contain Japanese characters
      expect(result.content).to match(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
    end

    context "with extraction prompt" do
      let(:extraction_prompt) { config.prompts[:extraction] }

      it "extracts opinions in expected JSON format" do
        comment = "環境問題への対策が必要だと思います。また、公共交通機関の充実も望みます。"

        # Use Structured Outputs (json_schema) like production code
        result = client.chat(
          system: extraction_prompt,
          user: comment,
          json_schema: Broadlistening::JsonSchemas::EXTRACTION
        )

        parsed = JSON.parse(result.content)

        # Should have extractedOpinionList key (guaranteed by schema)
        opinions = parsed["extractedOpinionList"]

        expect(opinions).to be_an(Array)
        expect(opinions).not_to be_empty
        opinions.each do |opinion|
          expect(opinion).to be_a(String)
          expect(opinion.length).to be > 5
        end
      end
    end

    context "with labelling prompt (json_mode)" do
      it "generates labels in expected JSON format" do
        # Use a prompt that explicitly requests JSON output
        system_prompt = <<~PROMPT
          あなたはクラスタ分析の専門家です。
          以下の意見グループに対して、適切なラベルと説明を付けてください。
          必ずJSON形式で回答してください。

          出力フォーマット:
          {"label": "ラベル名", "description": "このグループの説明"}
        PROMPT

        opinions = <<~TEXT
          - 環境問題への対策が必要
          - 温暖化対策を急ぐべき
          - 再生可能エネルギーの普及を
          - CO2削減の取り組みを強化すべき
        TEXT

        result = client.chat(
          system: system_prompt,
          user: opinions,
          json_mode: true
        )

        parsed = JSON.parse(result.content)

        expect(parsed).to have_key("label")
        expect(parsed).to have_key("description")
        expect(parsed["label"]).to be_a(String)
        expect(parsed["label"].length).to be > 0
        expect(parsed["description"]).to be_a(String)
        expect(parsed["description"].length).to be > 0
      end
    end

    context "with Structured Outputs (json_schema)" do
      it "generates labels using JSON schema enforcement" do
        system_prompt = <<~PROMPT
          あなたはクラスタ分析の専門家です。
          以下の意見グループに対して、適切なラベルと説明を付けてください。
        PROMPT

        opinions = <<~TEXT
          - 環境問題への対策が必要
          - 温暖化対策を急ぐべき
          - 再生可能エネルギーの普及を
          - CO2削減の取り組みを強化すべき
        TEXT

        result = client.chat(
          system: system_prompt,
          user: opinions,
          json_schema: Broadlistening::JsonSchemas::LABELLING
        )

        parsed = JSON.parse(result.content)

        # Structured Outputs guarantees schema compliance
        expect(parsed).to have_key("label")
        expect(parsed).to have_key("description")
        expect(parsed["label"]).to be_a(String)
        expect(parsed["label"]).not_to be_empty
        expect(parsed["description"]).to be_a(String)
        expect(parsed["description"]).not_to be_empty
      end

      it "extracts opinions using EXTRACTION schema" do
        system_prompt = config.prompts[:extraction]
        comment = "環境問題への対策が必要だと思います。また、公共交通機関の充実も望みます。"

        result = client.chat(
          system: system_prompt,
          user: comment,
          json_schema: Broadlistening::JsonSchemas::EXTRACTION
        )

        parsed = JSON.parse(result.content)

        expect(parsed).to have_key("extractedOpinionList")
        expect(parsed["extractedOpinionList"]).to be_an(Array)
        expect(parsed["extractedOpinionList"]).not_to be_empty
        parsed["extractedOpinionList"].each do |opinion|
          expect(opinion).to be_a(String)
        end
      end

      it "generates overview using OVERVIEW schema" do
        system_prompt = config.prompts[:overview]
        labels = <<~TEXT
          - 環境対策: 環境問題への取り組みに関する意見
          - 交通改善: 公共交通機関の充実を求める意見
          - 教育投資: 教育への投資増加を求める意見
        TEXT

        result = client.chat(
          system: system_prompt,
          user: labels,
          json_schema: Broadlistening::JsonSchemas::OVERVIEW
        )

        parsed = JSON.parse(result.content)

        expect(parsed).to have_key("summary")
        expect(parsed["summary"]).to be_a(String)
        expect(parsed["summary"]).not_to be_empty
      end
    end
  end

  describe "#embed" do
    it "returns valid embeddings for a single text" do
      embeddings = client.embed("テストテキスト")

      expect(embeddings).to be_an(Array)
      expect(embeddings.length).to eq(1)
      expect(embeddings.first).to be_an(Array)
      expect(embeddings.first.length).to eq(1536) # text-embedding-3-small dimension
      expect(embeddings.first).to all(be_a(Numeric))
      expect(embeddings.first).to all(be_between(-1, 1))
    end

    it "returns valid embeddings for multiple texts" do
      texts = [
        "環境問題への対策が必要",
        "公共交通機関の充実を希望",
        "教育への投資を増やすべき"
      ]

      embeddings = client.embed(texts)

      expect(embeddings).to be_an(Array)
      expect(embeddings.length).to eq(3)

      embeddings.each do |embedding|
        expect(embedding).to be_an(Array)
        expect(embedding.length).to eq(1536)
        expect(embedding).to all(be_a(Numeric))
        expect(embedding).to all(be_between(-1, 1))
      end
    end

    it "returns similar embeddings for same text" do
      text = "同じテキストは同じ埋め込みになるはず"

      embeddings1 = client.embed(text)
      embeddings2 = client.embed(text)

      # Calculate cosine similarity - should be very high for same text
      def cosine_similarity(a, b)
        dot = a.zip(b).sum { |x, y| x * y }
        norm_a = Math.sqrt(a.sum { |x| x * x })
        norm_b = Math.sqrt(b.sum { |x| x * x })
        dot / (norm_a * norm_b)
      end

      similarity = cosine_similarity(embeddings1.first, embeddings2.first)
      # OpenAI embeddings may have slight variations, but should be very similar
      expect(similarity).to be > 0.99
    end

    it "returns different embeddings for different texts" do
      embeddings = client.embed([ "環境問題", "教育問題" ])

      # Different texts should have different embeddings
      expect(embeddings[0]).not_to eq(embeddings[1])
    end

    it "handles batch embedding efficiently" do
      texts = 10.times.map { |i| "テスト意見 #{i}: これはテストコメントです。" }

      embeddings = client.embed(texts)

      expect(embeddings.length).to eq(10)
      embeddings.each do |embedding|
        expect(embedding.length).to eq(1536)
      end
    end
  end
end
