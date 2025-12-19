# frozen_string_literal: true

require "integration_helper"

RSpec.describe Broadlistening::Steps::Embedding do
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

  let(:context) { Broadlistening::Context.new }
  let(:step) { described_class.new(config, context) }

  describe "#execute" do
    context "with a small set of arguments" do
      before do
        context.arguments = [
          Broadlistening::Argument.new(
            arg_id: "A1_0",
            argument: "環境問題への対策が必要",
            comment_id: "1"
          ),
          Broadlistening::Argument.new(
            arg_id: "A2_0",
            argument: "公共交通機関の充実を望む",
            comment_id: "2"
          ),
          Broadlistening::Argument.new(
            arg_id: "A3_0",
            argument: "教育への投資を増やすべき",
            comment_id: "3"
          )
        ]
      end

      it "computes embeddings for all arguments" do
        step.execute

        context.arguments.each do |arg|
          expect(arg.embedding).to be_an(Array)
          expect(arg.embedding.length).to eq(1536) # text-embedding-3-small dimension
          expect(arg.embedding).to all(be_a(Numeric))
          expect(arg.embedding).to all(be_between(-1, 1))
        end
      end

      it "generates different embeddings for different opinions" do
        step.execute

        embeddings = context.arguments.map(&:embedding)

        # All embeddings should be different
        expect(embeddings.uniq.length).to eq(embeddings.length)
      end

      it "maintains argument data integrity" do
        step.execute

        expect(context.arguments[0].arg_id).to eq("A1_0")
        expect(context.arguments[0].argument).to eq("環境問題への対策が必要")
        expect(context.arguments[0].comment_id).to eq("1")
      end
    end

    context "with a larger set of arguments" do
      before do
        context.arguments = 20.times.map do |i|
          Broadlistening::Argument.new(
            arg_id: "A#{i}_0",
            argument: "これはテスト意見#{i}です。様々な観点からの意見を収集しています。",
            comment_id: i.to_s
          )
        end
      end

      it "computes embeddings for all arguments in batch" do
        step.execute

        expect(context.arguments.length).to eq(20)
        context.arguments.each do |arg|
          expect(arg.embedding).to be_an(Array)
          expect(arg.embedding.length).to eq(1536)
        end
      end

      it "preserves argument order" do
        step.execute

        context.arguments.each_with_index do |arg, i|
          expect(arg.arg_id).to eq("A#{i}_0")
        end
      end
    end

    context "with Japanese text of varying lengths" do
      before do
        context.arguments = [
          Broadlistening::Argument.new(
            arg_id: "A1_0",
            argument: "短い",
            comment_id: "1"
          ),
          Broadlistening::Argument.new(
            arg_id: "A2_0",
            argument: "中程度の長さの意見です。これくらいの文章量が一般的です。",
            comment_id: "2"
          ),
          Broadlistening::Argument.new(
            arg_id: "A3_0",
            argument: "非常に長い意見です。" * 20,
            comment_id: "3"
          )
        ]
      end

      it "handles varying text lengths correctly" do
        step.execute

        context.arguments.each do |arg|
          expect(arg.embedding).to be_an(Array)
          expect(arg.embedding.length).to eq(1536)
        end
      end
    end

    context "with special characters and formatting" do
      before do
        context.arguments = [
          Broadlistening::Argument.new(
            arg_id: "A1_0",
            argument: "改行を含む\n意見です",
            comment_id: "1"
          ),
          Broadlistening::Argument.new(
            arg_id: "A2_0",
            argument: "絵文字を含む意見です👍🎉",
            comment_id: "2"
          ),
          Broadlistening::Argument.new(
            arg_id: "A3_0",
            argument: "引用符「」や記号！？を含む意見",
            comment_id: "3"
          )
        ]
      end

      it "handles special characters correctly" do
        step.execute

        context.arguments.each do |arg|
          expect(arg.embedding).to be_an(Array)
          expect(arg.embedding.length).to eq(1536)
        end
      end
    end

    context "with semantically similar opinions" do
      before do
        context.arguments = [
          Broadlistening::Argument.new(
            arg_id: "A1_0",
            argument: "公園を増やしてほしい",
            comment_id: "1"
          ),
          Broadlistening::Argument.new(
            arg_id: "A2_0",
            argument: "緑地を増設してほしい",
            comment_id: "2"
          ),
          Broadlistening::Argument.new(
            arg_id: "A3_0",
            argument: "税金を下げてほしい",
            comment_id: "3"
          )
        ]
      end

      it "generates more similar embeddings for semantically related opinions" do
        step.execute

        # Calculate cosine similarity
        def cosine_similarity(a, b)
          dot = a.zip(b).sum { |x, y| x * y }
          norm_a = Math.sqrt(a.sum { |x| x * x })
          norm_b = Math.sqrt(b.sum { |x| x * x })
          dot / (norm_a * norm_b)
        end

        emb1 = context.arguments[0].embedding # 公園を増やしてほしい
        emb2 = context.arguments[1].embedding # 緑地を増設してほしい
        emb3 = context.arguments[2].embedding # 税金を下げてほしい

        sim_1_2 = cosine_similarity(emb1, emb2) # Similar topics
        sim_1_3 = cosine_similarity(emb1, emb3) # Different topics

        # Semantically similar opinions should have higher similarity
        expect(sim_1_2).to be > sim_1_3
      end
    end

    context "with empty arguments array" do
      before do
        context.arguments = []
      end

      it "handles empty input gracefully" do
        expect { step.execute }.not_to raise_error
        expect(context.arguments).to be_empty
      end
    end
  end
end
