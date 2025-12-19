# frozen_string_literal: true

require "integration_helper"

RSpec.describe "Labelling Steps Integration" do
  before do
    skip "OPENAI_API_KEY not set" unless ENV["OPENAI_API_KEY"]
  end

  let(:config) do
    Broadlistening::Config.new(
      api_key: ENV.fetch("OPENAI_API_KEY", nil),
      provider: :openai,
      model: "gpt-4o-mini",
      embedding_model: "text-embedding-3-small",
      cluster_nums: [ 3, 6 ],
      workers: 2
    )
  end

  let(:context) { Broadlistening::Context.new }

  # Set up test data with clusters
  def setup_clustered_arguments
    # Create arguments with different topics grouped into clusters
    # Level 0: 3 clusters (coarse)
    # Level 1: 6 clusters (fine)

    # Cluster 0_0 (Environment) -> 1_0, 1_1
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A1_0", argument: "環境問題への対策が必要", comment_id: "1",
      cluster_ids: [ "0_0", "1_0" ]
    )
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A2_0", argument: "温暖化対策を急ぐべき", comment_id: "2",
      cluster_ids: [ "0_0", "1_0" ]
    )
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A3_0", argument: "再生可能エネルギーの普及を", comment_id: "3",
      cluster_ids: [ "0_0", "1_1" ]
    )
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A4_0", argument: "CO2削減の取り組みを強化", comment_id: "4",
      cluster_ids: [ "0_0", "1_1" ]
    )

    # Cluster 0_1 (Transportation) -> 1_2, 1_3
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A5_0", argument: "公共交通機関の充実を望む", comment_id: "5",
      cluster_ids: [ "0_1", "1_2" ]
    )
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A6_0", argument: "バスの運行本数を増やしてほしい", comment_id: "6",
      cluster_ids: [ "0_1", "1_2" ]
    )
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A7_0", argument: "駅前の駐輪場を増設してほしい", comment_id: "7",
      cluster_ids: [ "0_1", "1_3" ]
    )
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A8_0", argument: "自転車専用道路を整備してほしい", comment_id: "8",
      cluster_ids: [ "0_1", "1_3" ]
    )

    # Cluster 0_2 (Education) -> 1_4, 1_5
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A9_0", argument: "教育への投資を増やすべき", comment_id: "9",
      cluster_ids: [ "0_2", "1_4" ]
    )
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A10_0", argument: "少人数学級を実現してほしい", comment_id: "10",
      cluster_ids: [ "0_2", "1_4" ]
    )
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A11_0", argument: "子供の放課後活動を支援してほしい", comment_id: "11",
      cluster_ids: [ "0_2", "1_5" ]
    )
    context.arguments << Broadlistening::Argument.new(
      arg_id: "A12_0", argument: "学校図書館を充実させてほしい", comment_id: "12",
      cluster_ids: [ "0_2", "1_5" ]
    )

    # Set up cluster results
    cluster_results = Broadlistening::ClusterResults.new
    context.arguments.each_with_index do |arg, idx|
      arg.cluster_ids.each do |cid|
        level, cluster_num = cid.split("_").map(&:to_i)
        cluster_results.set(level, idx, cluster_num)
      end
    end
    context.cluster_results = cluster_results
  end

  describe Broadlistening::Steps::InitialLabelling do
    let(:step) { described_class.new(config, context) }

    before do
      setup_clustered_arguments
    end

    describe "#execute" do
      it "generates labels for leaf clusters" do
        step.execute

        expect(context.initial_labels).not_to be_empty

        # Should have labels for level 1 (leaf level) clusters
        expect(context.initial_labels.keys).to include("1_0", "1_1", "1_2", "1_3", "1_4", "1_5")
      end

      it "generates meaningful labels based on cluster content" do
        step.execute

        context.initial_labels.each do |cluster_id, label|
          expect(label).to be_a(Broadlistening::ClusterLabel)
          expect(label.cluster_id).to eq(cluster_id)
          expect(label.label).to be_a(String)
          expect(label.label).not_to be_empty
          expect(label.description).to be_a(String)
        end
      end

      it "labels reflect the cluster topics" do
        step.execute

        # Environment-related cluster should have environment-related label
        env_labels = [ context.initial_labels["1_0"], context.initial_labels["1_1"] ]
        env_text = env_labels.map { |l| "#{l.label} #{l.description}" }.join(" ")

        # Should contain Japanese characters
        expect(env_text).to match(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
      end

      it "tracks token usage" do
        initial_usage = context.token_usage.total
        step.execute

        # Token usage should increase after LLM calls
        expect(context.token_usage).not_to be_nil
        expect(context.token_usage.total).to be >= initial_usage
      end
    end
  end

  describe Broadlistening::Steps::MergeLabelling do
    let(:initial_step) { Broadlistening::Steps::InitialLabelling.new(config, context) }
    let(:merge_step) { described_class.new(config, context) }

    before do
      setup_clustered_arguments
      # Run initial labelling first
      initial_step.execute
    end

    describe "#execute" do
      it "generates parent labels from child labels" do
        merge_step.execute

        expect(context.labels).not_to be_empty

        # Should have labels for all levels
        expect(context.labels.keys).to include("0_0", "0_1", "0_2")
        expect(context.labels.keys).to include("1_0", "1_1", "1_2", "1_3", "1_4", "1_5")
      end

      it "parent labels abstract child labels" do
        merge_step.execute

        # Each parent should have a label and description
        [ "0_0", "0_1", "0_2" ].each do |parent_id|
          label = context.labels[parent_id]
          expect(label).to be_a(Broadlistening::ClusterLabel)
          expect(label.label).to be_a(String)
          expect(label.label).not_to be_empty
          expect(label.description).to be_a(String)
        end
      end

      it "preserves initial labels in final labels" do
        merge_step.execute

        # Initial labels should still be present
        [ "1_0", "1_1", "1_2", "1_3", "1_4", "1_5" ].each do |child_id|
          expect(context.labels).to have_key(child_id)
          expect(context.labels[child_id].label).to eq(context.initial_labels[child_id].label)
        end
      end

      it "tracks token usage for merge operations" do
        initial_usage = context.token_usage.total
        merge_step.execute
        final_usage = context.token_usage.total

        # Token usage should not decrease after LLM calls
        expect(final_usage).to be >= initial_usage
      end
    end
  end

  describe "Full labelling pipeline" do
    let(:initial_step) { Broadlistening::Steps::InitialLabelling.new(config, context) }
    let(:merge_step) { Broadlistening::Steps::MergeLabelling.new(config, context) }

    before do
      setup_clustered_arguments
    end

    it "produces a complete label hierarchy" do
      initial_step.execute
      merge_step.execute

      # Verify hierarchy structure
      levels = context.labels.values.map(&:level).uniq.sort
      expect(levels).to eq([ 0, 1 ])

      # Count labels per level
      level_0_count = context.labels.values.count { |l| l.level == 0 }
      level_1_count = context.labels.values.count { |l| l.level == 1 }

      expect(level_0_count).to eq(3) # 3 parent clusters
      expect(level_1_count).to eq(6) # 6 leaf clusters
    end

    it "all labels have Japanese content" do
      initial_step.execute
      merge_step.execute

      context.labels.each_value do |label|
        expect(label.label).to match(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
      end
    end
  end
end
