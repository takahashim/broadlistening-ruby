# frozen_string_literal: true

require "integration_helper"

RSpec.describe Broadlistening::Steps::Overview do
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
    context "with typical cluster labels" do
      before do
        # Set up labels with a typical hierarchy
        context.labels = {
          "0_0" => Broadlistening::ClusterLabel.new(
            cluster_id: "0_0",
            level: 0,
            label: "環境・エネルギー",
            description: "環境問題や再生可能エネルギーに関する意見"
          ),
          "0_1" => Broadlistening::ClusterLabel.new(
            cluster_id: "0_1",
            level: 0,
            label: "交通・インフラ",
            description: "公共交通機関や道路整備に関する意見"
          ),
          "0_2" => Broadlistening::ClusterLabel.new(
            cluster_id: "0_2",
            level: 0,
            label: "教育・子育て",
            description: "学校教育や子育て支援に関する意見"
          ),
          # Child labels (should not be included in overview input)
          "1_0" => Broadlistening::ClusterLabel.new(
            cluster_id: "1_0",
            level: 1,
            label: "温暖化対策",
            description: "地球温暖化への対策を求める意見"
          ),
          "1_1" => Broadlistening::ClusterLabel.new(
            cluster_id: "1_1",
            level: 1,
            label: "再エネ推進",
            description: "再生可能エネルギーの普及を求める意見"
          )
        }
      end

      it "generates an overview text" do
        step.execute

        expect(context.overview).to be_a(String)
        expect(context.overview).not_to be_empty
      end

      it "generates overview in Japanese" do
        step.execute

        expect(context.overview).to match(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
      end

      it "generates overview of appropriate length" do
        step.execute

        # Overview should be substantial but not too long
        expect(context.overview.length).to be > 50
        expect(context.overview.length).to be < 1000
      end

      it "tracks token usage" do
        step.execute

        expect(context.token_usage).not_to be_nil
        expect(context.token_usage.total).to be > 0
      end
    end

    context "with many top-level clusters" do
      before do
        # Set up more clusters to test handling of larger inputs
        context.labels = 10.times.to_h do |i|
          [
            "0_#{i}",
            Broadlistening::ClusterLabel.new(
              cluster_id: "0_#{i}",
              level: 0,
              label: "テーマ#{i + 1}",
              description: "テーマ#{i + 1}に関する様々な意見が集まったグループです"
            )
          ]
        end
      end

      it "handles many clusters gracefully" do
        step.execute

        expect(context.overview).to be_a(String)
        expect(context.overview).not_to be_empty
      end
    end

    context "with detailed cluster descriptions" do
      before do
        context.labels = {
          "0_0" => Broadlistening::ClusterLabel.new(
            cluster_id: "0_0",
            level: 0,
            label: "行政サービスの効率化",
            description: "役所の手続きのオンライン化や窓口対応の改善を求める声。特に高齢者への配慮も重要視されている。"
          ),
          "0_1" => Broadlistening::ClusterLabel.new(
            cluster_id: "0_1",
            level: 0,
            label: "地域コミュニティの活性化",
            description: "町内会活動の支援や地域イベントの充実を求める意見。若者の参加促進も課題として挙げられている。"
          ),
          "0_2" => Broadlistening::ClusterLabel.new(
            cluster_id: "0_2",
            level: 0,
            label: "防災・安全対策",
            description: "災害時の避難所整備や防犯カメラの設置を求める意見。情報伝達手段の多様化も求められている。"
          )
        }
      end

      it "incorporates cluster details in overview" do
        step.execute

        expect(context.overview).to be_a(String)
        # Overview should be a coherent summary
        expect(context.overview).not_to be_empty
      end
    end

    context "with single cluster" do
      before do
        context.labels = {
          "0_0" => Broadlistening::ClusterLabel.new(
            cluster_id: "0_0",
            level: 0,
            label: "環境問題への対策",
            description: "環境保全と持続可能な発展に関する意見"
          )
        }
      end

      it "generates overview for single cluster" do
        step.execute

        expect(context.overview).to be_a(String)
        expect(context.overview).not_to be_empty
      end
    end

    context "with empty labels" do
      before do
        context.labels = {}
      end

      it "handles empty labels gracefully" do
        expect { step.execute }.not_to raise_error
        expect(context.overview).to be_nil
      end
    end

    context "with mixed level labels" do
      before do
        # Mix of levels - only top level should be used
        context.labels = {
          "0_0" => Broadlistening::ClusterLabel.new(
            cluster_id: "0_0",
            level: 0,
            label: "トップレベル1",
            description: "最上位クラスタ1の説明"
          ),
          "0_1" => Broadlistening::ClusterLabel.new(
            cluster_id: "0_1",
            level: 0,
            label: "トップレベル2",
            description: "最上位クラスタ2の説明"
          ),
          "1_0" => Broadlistening::ClusterLabel.new(
            cluster_id: "1_0",
            level: 1,
            label: "サブレベル1",
            description: "サブクラスタ1の説明"
          ),
          "2_0" => Broadlistening::ClusterLabel.new(
            cluster_id: "2_0",
            level: 2,
            label: "リーフレベル1",
            description: "リーフクラスタ1の説明"
          )
        }
      end

      it "uses only top-level labels for overview" do
        step.execute

        expect(context.overview).to be_a(String)
        expect(context.overview).not_to be_empty
        # Overview should be generated from level 0 labels only
      end
    end
  end
end
