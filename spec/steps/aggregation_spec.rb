# frozen_string_literal: true

RSpec.describe Broadlistening::Steps::Aggregation do
  let(:config_options) do
    {
      api_key: "test-api-key",
      model: "gpt-4o-mini",
      cluster_nums: [2, 5]
    }
  end

  let(:config) { Broadlistening::Config.new(config_options) }

  let(:comments) do
    [
      { id: "1", body: "環境問題への対策が必要です", proposal_id: "123" },
      { id: "2", body: "公共交通機関の充実を希望します", proposal_id: "123" },
      { id: "3", body: "教育の質を向上させるべき", proposal_id: "123" }
    ]
  end

  let(:arguments) do
    [
      { arg_id: "A1_0", argument: "環境問題への対策が必要", comment_id: "1", x: 0.5, y: 0.3, cluster_ids: %w[0 1_0 2_0] },
      { arg_id: "A2_0", argument: "公共交通機関の充実", comment_id: "2", x: 0.7, y: 0.2, cluster_ids: %w[0 1_0 2_1] },
      { arg_id: "A3_0", argument: "教育の質向上", comment_id: "3", x: -0.3, y: 0.8, cluster_ids: %w[0 1_1 2_2] }
    ]
  end

  let(:labels) do
    {
      "1_0" => { cluster_id: "1_0", level: 1, label: "インフラ", description: "インフラに関する意見" },
      "1_1" => { cluster_id: "1_1", level: 1, label: "教育", description: "教育に関する意見" },
      "2_0" => { cluster_id: "2_0", level: 2, label: "環境", description: "環境問題への対策" },
      "2_1" => { cluster_id: "2_1", level: 2, label: "交通", description: "交通機関の改善" },
      "2_2" => { cluster_id: "2_2", level: 2, label: "学校教育", description: "学校教育の質向上" }
    }
  end

  let(:cluster_results) do
    {
      1 => [0, 0, 1],
      2 => [0, 1, 2]
    }
  end

  let(:context) do
    {
      comments: comments,
      arguments: arguments,
      labels: labels,
      cluster_results: cluster_results,
      overview: "テスト概要"
    }
  end

  subject(:step) { described_class.new(config, context) }

  describe "#execute" do
    let(:result) { step.execute[:result] }

    describe "top-level structure" do
      it "includes all required fields" do
        expect(result).to have_key(:arguments)
        expect(result).to have_key(:clusters)
        expect(result).to have_key(:comments)
        expect(result).to have_key(:propertyMap)
        expect(result).to have_key(:translations)
        expect(result).to have_key(:overview)
        expect(result).to have_key(:config)
        expect(result).to have_key(:comment_num)
      end

      it "sets comment_num to the number of comments" do
        expect(result[:comment_num]).to eq(3)
      end

      it "includes the overview text" do
        expect(result[:overview]).to eq("テスト概要")
      end

      it "includes propertyMap as empty object" do
        expect(result[:propertyMap]).to eq({})
      end

      it "includes translations as empty object" do
        expect(result[:translations]).to eq({})
      end
    end

    describe "arguments array" do
      it "includes all arguments" do
        expect(result[:arguments].size).to eq(3)
      end

      it "includes required fields for each argument" do
        arg = result[:arguments].first
        expect(arg).to have_key(:arg_id)
        expect(arg).to have_key(:argument)
        expect(arg).to have_key(:comment_id)
        expect(arg).to have_key(:x)
        expect(arg).to have_key(:y)
        expect(arg).to have_key(:p)
        expect(arg).to have_key(:cluster_ids)
      end

      it "sets comment_id as integer" do
        arg = result[:arguments].first
        expect(arg[:comment_id]).to eq(1)
        expect(arg[:comment_id]).to be_a(Integer)
      end

      it "sets p to 0 (reserved for future use)" do
        result[:arguments].each do |arg|
          expect(arg[:p]).to eq(0)
        end
      end

      it "converts x and y to floats" do
        arg = result[:arguments].first
        expect(arg[:x]).to be_a(Float)
        expect(arg[:y]).to be_a(Float)
      end

      it "extracts comment_id from arg_id when not provided" do
        arguments_without_comment_id = arguments.map { |a| a.except(:comment_id) }
        context_without_comment_id = context.merge(arguments: arguments_without_comment_id)
        step_without_comment_id = described_class.new(config, context_without_comment_id)
        result = step_without_comment_id.execute[:result]

        expect(result[:arguments].first[:comment_id]).to eq(1)
        expect(result[:arguments][1][:comment_id]).to eq(2)
        expect(result[:arguments][2][:comment_id]).to eq(3)
      end
    end

    describe "clusters array" do
      it "includes root cluster and all labeled clusters" do
        # 1 root + 2 level-1 + 3 level-2 = 6
        expect(result[:clusters].size).to eq(6)
      end

      it "includes required fields for each cluster" do
        cluster = result[:clusters].first
        expect(cluster).to have_key(:level)
        expect(cluster).to have_key(:id)
        expect(cluster).to have_key(:label)
        expect(cluster).to have_key(:takeaway)
        expect(cluster).to have_key(:value)
        expect(cluster).to have_key(:parent)
        expect(cluster).to have_key(:density_rank_percentile)
      end

      it "uses 'takeaway' instead of 'description'" do
        cluster = result[:clusters].find { |c| c[:id] == "1_0" }
        expect(cluster[:takeaway]).to eq("インフラに関する意見")
        expect(cluster).not_to have_key(:description)
      end

      it "uses 'value' instead of 'count'" do
        cluster = result[:clusters].find { |c| c[:id] == "1_0" }
        expect(cluster[:value]).to eq(2) # A1_0 and A2_0 belong to 1_0
        expect(cluster).not_to have_key(:count)
      end

      it "sets density_rank_percentile to nil" do
        result[:clusters].each do |cluster|
          expect(cluster[:density_rank_percentile]).to be_nil
        end
      end

      describe "root cluster" do
        let(:root) { result[:clusters].find { |c| c[:id] == "0" } }

        it "has level 0" do
          expect(root[:level]).to eq(0)
        end

        it "has label '全体'" do
          expect(root[:label]).to eq("全体")
        end

        it "has empty string parent" do
          expect(root[:parent]).to eq("")
        end

        it "has value equal to total arguments" do
          expect(root[:value]).to eq(3)
        end
      end

      describe "parent-child relationships" do
        it "sets parent to '0' for level-1 clusters" do
          level_1_clusters = result[:clusters].select { |c| c[:level] == 1 }
          level_1_clusters.each do |cluster|
            expect(cluster[:parent]).to eq("0")
          end
        end

        it "sets correct parent for level-2 clusters" do
          cluster_2_0 = result[:clusters].find { |c| c[:id] == "2_0" }
          cluster_2_1 = result[:clusters].find { |c| c[:id] == "2_1" }
          cluster_2_2 = result[:clusters].find { |c| c[:id] == "2_2" }

          expect(cluster_2_0[:parent]).to eq("1_0")
          expect(cluster_2_1[:parent]).to eq("1_0")
          expect(cluster_2_2[:parent]).to eq("1_1")
        end
      end

      it "sorts clusters by level and id" do
        levels = result[:clusters].map { |c| c[:level] }
        expect(levels).to eq(levels.sort)
      end
    end

    describe "comments object" do
      it "is keyed by comment_id as string" do
        expect(result[:comments]).to have_key("1")
        expect(result[:comments]).to have_key("2")
        expect(result[:comments]).to have_key("3")
      end

      it "includes comment body" do
        expect(result[:comments]["1"][:comment]).to eq("環境問題への対策が必要です")
      end

      it "only includes comments with extracted arguments" do
        # Add a comment without arguments
        comments_with_extra = comments + [{ id: "4", body: "空のコメント", proposal_id: "123" }]
        context_with_extra = context.merge(comments: comments_with_extra)
        step_with_extra = described_class.new(config, context_with_extra)
        result = step_with_extra.execute[:result]

        expect(result[:comments]).to have_key("1")
        expect(result[:comments]).not_to have_key("4")
      end
    end
  end

  describe "compatibility with Kouchou-AI output format" do
    let(:result) { step.execute[:result] }

    it "matches the expected JSON structure" do
      # Top level keys should match Python output
      expected_keys = %i[arguments clusters comments propertyMap translations overview config comment_num]
      expect(result.keys).to match_array(expected_keys)
    end

    it "argument structure matches Python output" do
      arg = result[:arguments].first
      expected_keys = %i[arg_id argument comment_id x y p cluster_ids]
      expect(arg.keys).to match_array(expected_keys)
    end

    it "cluster structure matches Python output" do
      cluster = result[:clusters].find { |c| c[:level] == 1 }
      expected_keys = %i[level id label takeaway value parent density_rank_percentile]
      expect(cluster.keys).to match_array(expected_keys)
    end
  end
end
