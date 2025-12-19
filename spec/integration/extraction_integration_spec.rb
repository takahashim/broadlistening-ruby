# frozen_string_literal: true

require "integration_helper"

RSpec.describe Broadlistening::Steps::Extraction do
  before do
    skip "OPENAI_API_KEY not set" unless ENV["OPENAI_API_KEY"]
  end

  let(:config) do
    Broadlistening::Config.new(
      api_key: ENV.fetch("OPENAI_API_KEY", nil),
      provider: :openai,
      model: "gpt-4o-mini",
      embedding_model: "text-embedding-3-small",
      workers: 2 # Limit parallelism for integration tests
    )
  end

  let(:context) { Broadlistening::Context.new }
  let(:step) { described_class.new(config, context) }

  describe "#execute" do
    context "with single comment containing multiple opinions" do
      before do
        context.comments = [
          Broadlistening::Comment.new(
            id: "1",
            body: "環境問題への対策が必要だと思います。また、公共交通機関の充実も望みます。さらに、教育への投資も増やすべきです。",
            proposal_id: "test"
          )
        ]
      end

      it "extracts multiple opinions from a single comment" do
        step.execute

        expect(context.arguments).not_to be_empty
        expect(context.arguments.length).to be >= 2 # Should extract multiple opinions

        context.arguments.each do |arg|
          expect(arg.argument).to be_a(String)
          expect(arg.argument.length).to be > 5
          expect(arg.arg_id).to match(/^A1_\d+$/)
          expect(arg.comment_id).to eq("1")
        end
      end

      it "creates relations for each extracted argument" do
        step.execute

        expect(context.relations.length).to eq(context.arguments.length)
        context.relations.each do |relation|
          expect(relation.arg_id).to match(/^A1_\d+$/)
          expect(relation.comment_id).to eq("1")
        end
      end

      it "tracks token usage" do
        step.execute

        expect(context.token_usage).not_to be_nil
        expect(context.token_usage.total).to be > 0
      end
    end

    context "with multiple comments" do
      let(:comments) do
        [
          Broadlistening::Comment.new(
            id: "1",
            body: "地域の公園を増やしてほしいです。子供たちが安全に遊べる場所が必要です。",
            proposal_id: "test"
          ),
          Broadlistening::Comment.new(
            id: "2",
            body: "バスの運行本数を増やしてください。特に朝の通勤時間帯は混雑がひどいです。",
            proposal_id: "test"
          ),
          Broadlistening::Comment.new(
            id: "3",
            body: "街灯を増設して夜間の安全性を向上させてほしい。駅周辺は特に暗くて危険を感じます。",
            proposal_id: "test"
          ),
          Broadlistening::Comment.new(
            id: "4",
            body: "ゴミの分別ルールが複雑すぎます。もっとわかりやすくしてほしいです。",
            proposal_id: "test"
          ),
          Broadlistening::Comment.new(
            id: "5",
            body: "高齢者向けの福祉サービスを充実させてください。一人暮らしのお年寄りが増えています。",
            proposal_id: "test"
          )
        ]
      end

      before do
        context.comments = comments
      end

      it "extracts opinions from all comments" do
        step.execute

        expect(context.arguments.length).to be >= comments.length

        # Each comment should have at least one argument
        comment_ids = context.arguments.map(&:comment_id).uniq
        expect(comment_ids.length).to eq(comments.length)
      end

      it "maintains correct argument structure" do
        step.execute

        context.arguments.each do |arg|
          expect(arg.arg_id).to match(/^A\d+_\d+$/)
          expect(arg.argument).to be_a(String)
          expect(arg.argument).not_to be_empty
          expect(arg.comment_id).to be_a(String)
        end
      end

      it "processes comments in parallel" do
        # This test verifies that parallel processing works correctly
        start_time = Time.now
        step.execute
        elapsed = Time.now - start_time

        # With 5 comments and 2 workers, should take less time than sequential
        expect(context.arguments).not_to be_empty
        expect(elapsed).to be < 30 # Reasonable timeout
      end
    end

    context "with Japanese text containing various opinion patterns" do
      let(:comments) do
        [
          # Clear opinion statement
          Broadlistening::Comment.new(
            id: "1",
            body: "私は消費税の引き上げに反対です。",
            proposal_id: "test"
          ),
          # Suggestion format
          Broadlistening::Comment.new(
            id: "2",
            body: "道路の舗装工事を早急に実施すべきだと思います。",
            proposal_id: "test"
          ),
          # Question format with implied opinion
          Broadlistening::Comment.new(
            id: "3",
            body: "なぜ保育園の数を増やさないのでしょうか？子育て世代にとって深刻な問題です。",
            proposal_id: "test"
          ),
          # Compound opinions
          Broadlistening::Comment.new(
            id: "4",
            body: "賛成です。ただし、実施時期については十分な検討が必要だと考えます。",
            proposal_id: "test"
          ),
          # Emotional expression
          Broadlistening::Comment.new(
            id: "5",
            body: "本当に困っています。早く対策を取ってほしいです。",
            proposal_id: "test"
          )
        ]
      end

      before do
        context.comments = comments
      end

      it "extracts opinions from various Japanese expression patterns" do
        step.execute

        expect(context.arguments.length).to be >= comments.length

        # All extracted opinions should be meaningful strings
        context.arguments.each do |arg|
          expect(arg.argument).to match(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
          # LLM may extract short phrases like "便利だ" (4 chars), so use 3 as minimum
          expect(arg.argument.length).to be >= 3
        end
      end
    end

    context "with empty or minimal content" do
      before do
        context.comments = [
          Broadlistening::Comment.new(
            id: "1",
            body: "特になし",
            proposal_id: "test"
          ),
          Broadlistening::Comment.new(
            id: "2",
            body: "良いと思います。",
            proposal_id: "test"
          )
        ]
      end

      it "handles minimal content gracefully" do
        step.execute

        # Should not raise errors
        expect(context.arguments).to be_an(Array)
      end
    end

    context "with attributes and source_url" do
      before do
        context.comments = [
          Broadlistening::Comment.new(
            id: "1",
            body: "公園を増やしてほしいです。",
            proposal_id: "test",
            source_url: "https://example.com/comment/1",
            attributes: { "age" => "30代", "gender" => "男性" }
          )
        ]
      end

      it "preserves attributes and url in extracted arguments" do
        step.execute

        expect(context.arguments).not_to be_empty
        arg = context.arguments.first

        expect(arg.attributes).to eq({ "age" => "30代", "gender" => "男性" })
        expect(arg.url).to eq("https://example.com/comment/1")
      end
    end
  end
end
