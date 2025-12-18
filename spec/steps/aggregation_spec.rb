# frozen_string_literal: true

require "tmpdir"
require "csv"

RSpec.describe Broadlistening::Steps::Aggregation do
  let(:config_options) do
    {
      api_key: "test-api-key",
      model: "gpt-4o-mini",
      cluster_nums: [ 2, 5 ]
    }
  end

  let(:config) { Broadlistening::Config.new(config_options) }

  let(:comments) do
    [
      Broadlistening::Comment.new(id: "1", body: "環境問題への対策が必要です", proposal_id: "123"),
      Broadlistening::Comment.new(id: "2", body: "公共交通機関の充実を希望します", proposal_id: "123"),
      Broadlistening::Comment.new(id: "3", body: "教育の質を向上させるべき", proposal_id: "123")
    ]
  end

  let(:arguments) do
    [
      Broadlistening::Argument.new(arg_id: "A1_0", argument: "環境問題への対策が必要", comment_id: "1", x: 0.5, y: 0.3, cluster_ids: %w[0 1_0 2_0]),
      Broadlistening::Argument.new(arg_id: "A2_0", argument: "公共交通機関の充実", comment_id: "2", x: 0.7, y: 0.2, cluster_ids: %w[0 1_0 2_1]),
      Broadlistening::Argument.new(arg_id: "A3_0", argument: "教育の質向上", comment_id: "3", x: -0.3, y: 0.8, cluster_ids: %w[0 1_1 2_2])
    ]
  end

  let(:labels) do
    {
      "1_0" => Broadlistening::ClusterLabel.new(cluster_id: "1_0", level: 1, label: "インフラ", description: "インフラに関する意見"),
      "1_1" => Broadlistening::ClusterLabel.new(cluster_id: "1_1", level: 1, label: "教育", description: "教育に関する意見"),
      "2_0" => Broadlistening::ClusterLabel.new(cluster_id: "2_0", level: 2, label: "環境", description: "環境問題への対策"),
      "2_1" => Broadlistening::ClusterLabel.new(cluster_id: "2_1", level: 2, label: "交通", description: "交通機関の改善"),
      "2_2" => Broadlistening::ClusterLabel.new(cluster_id: "2_2", level: 2, label: "学校教育", description: "学校教育の質向上")
    }
  end

  let(:cluster_results) do
    Broadlistening::ClusterResults.from_h({
      1 => [ 0, 0, 1 ],
      2 => [ 0, 1, 2 ]
    })
  end

  let(:context) do
    ctx = Broadlistening::Context.new
    ctx.comments = comments
    ctx.arguments = arguments
    ctx.labels = labels
    ctx.cluster_results = cluster_results
    ctx.overview = "テスト概要"
    ctx
  end

  subject(:step) { described_class.new(config, context) }

  describe "#execute" do
    let(:result) do
      step.execute
      context.result.to_h
    end

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
        arguments_without_comment_id = [
          Broadlistening::Argument.new(arg_id: "A1_0", argument: "test1", comment_id: nil, x: 0.5, y: 0.3, cluster_ids: %w[0 1_0]),
          Broadlistening::Argument.new(arg_id: "A2_0", argument: "test2", comment_id: nil, x: 0.7, y: 0.2, cluster_ids: %w[0 1_0]),
          Broadlistening::Argument.new(arg_id: "A3_0", argument: "test3", comment_id: nil, x: -0.3, y: 0.8, cluster_ids: %w[0 1_1])
        ]
        context.arguments = arguments_without_comment_id
        step.execute

        result_h = context.result.to_h
        expect(result_h[:arguments].first[:comment_id]).to eq(1)
        expect(result_h[:arguments][1][:comment_id]).to eq(2)
        expect(result_h[:arguments][2][:comment_id]).to eq(3)
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

      it "calculates density_rank_percentile for clusters with points" do
        result[:clusters].each do |cluster|
          expect(cluster).to have_key(:density_rank_percentile)
          next if cluster[:level] == 0 # Root cluster has no density

          # Clusters with points should have density_rank_percentile
          if cluster[:value] > 0
            expect(cluster[:density_rank_percentile]).to be_a(Float).or(be_nil)
          end
        end
      end

      it "sets density_rank_percentile to nil for root cluster" do
        root = result[:clusters].find { |c| c[:id] == "0" }
        expect(root[:density_rank_percentile]).to be_nil
      end

      it "calculates density_rank_percentile within each level" do
        level_1_clusters = result[:clusters].select { |c| c[:level] == 1 }
        percentiles = level_1_clusters.map { |c| c[:density_rank_percentile] }.compact

        # All non-nil percentiles should be between 0 and 1
        percentiles.each do |p|
          expect(p).to be_between(0, 1)
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
        context.comments << Broadlistening::Comment.new(id: "4", body: "空のコメント", proposal_id: "123")
        step.execute

        result_h = context.result.to_h
        expect(result_h[:comments]).to have_key("1")
        expect(result_h[:comments]).not_to have_key("4")
      end
    end
  end

  describe "compatibility with Kouchou-AI output format" do
    let(:result) do
      step.execute
      context.result.to_h
    end

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

  describe "attributes support" do
    let(:arguments_with_attributes) do
      [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "環境問題への対策が必要",
          comment_id: "1",
          x: 0.5,
          y: 0.3,
          cluster_ids: %w[0 1_0 2_0],
          attributes: { "age" => "30代", "region" => "東京" }
        ),
        Broadlistening::Argument.new(
          arg_id: "A2_0",
          argument: "公共交通機関の充実",
          comment_id: "2",
          x: 0.7,
          y: 0.2,
          cluster_ids: %w[0 1_0 2_1]
        )
      ]
    end

    before do
      context.arguments = arguments_with_attributes
    end

    it "includes attributes when present" do
      step.execute
      result_h = context.result.to_h
      arg_with_attrs = result_h[:arguments].find { |a| a[:arg_id] == "A1_0" }
      expect(arg_with_attrs[:attributes]).to eq({ "age" => "30代", "region" => "東京" })
    end

    it "does not include attributes key when not present" do
      step.execute
      result_h = context.result.to_h
      arg_without_attrs = result_h[:arguments].find { |a| a[:arg_id] == "A2_0" }
      expect(arg_without_attrs).not_to have_key(:attributes)
    end
  end

  describe "propertyMap support" do
    let(:config_with_properties) do
      Broadlistening::Config.new(config_options.merge(
        hidden_properties: {
          "source" => [ "X API" ],
          "age" => [ 20, 25 ]
        }
      ))
    end

    let(:arguments_with_properties) do
      [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "環境問題への対策が必要",
          comment_id: "1",
          x: 0.5,
          y: 0.3,
          cluster_ids: %w[0 1_0 2_0],
          properties: { "source" => "twitter", "age" => 35 }
        ),
        Broadlistening::Argument.new(
          arg_id: "A2_0",
          argument: "公共交通機関の充実",
          comment_id: "2",
          x: 0.7,
          y: 0.2,
          cluster_ids: %w[0 1_0 2_1],
          properties: { "source" => "facebook", "age" => nil }
        ),
        Broadlistening::Argument.new(
          arg_id: "A3_0",
          argument: "教育の質向上",
          comment_id: "3",
          x: -0.3,
          y: 0.8,
          cluster_ids: %w[0 1_1 2_2]
        )
      ]
    end

    let(:step_with_properties) { described_class.new(config_with_properties, context) }

    before do
      context.arguments = arguments_with_properties
    end

    it "builds propertyMap with property names as keys" do
      step_with_properties.execute
      property_map = context.result.to_h[:propertyMap]
      expect(property_map.keys).to match_array(%w[source age])
    end

    it "maps arg_id to property values" do
      step_with_properties.execute
      property_map = context.result.to_h[:propertyMap]
      expect(property_map["source"]["A1_0"]).to eq("twitter")
      expect(property_map["source"]["A2_0"]).to eq("facebook")
      expect(property_map["age"]["A1_0"]).to eq(35)
    end

    it "handles nil property values" do
      step_with_properties.execute
      property_map = context.result.to_h[:propertyMap]
      expect(property_map["age"]["A2_0"]).to be_nil
    end

    it "does not include arguments without properties in propertyMap" do
      step_with_properties.execute
      property_map = context.result.to_h[:propertyMap]
      expect(property_map["source"]).not_to have_key("A3_0")
      expect(property_map["age"]).not_to have_key("A3_0")
    end

    context "when no hidden_properties configured" do
      it "returns empty propertyMap" do
        step.execute
        expect(context.result.to_h[:propertyMap]).to eq({})
      end
    end
  end

  describe "url support" do
    let(:arguments_with_url) do
      [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "環境問題への対策が必要",
          comment_id: "1",
          x: 0.5,
          y: 0.3,
          cluster_ids: %w[0 1_0 2_0],
          url: "https://example.com/comment/1"
        ),
        Broadlistening::Argument.new(
          arg_id: "A2_0",
          argument: "公共交通機関の充実",
          comment_id: "2",
          x: 0.7,
          y: 0.2,
          cluster_ids: %w[0 1_0 2_1]
        )
      ]
    end

    before do
      context.arguments = arguments_with_url
    end

    context "when enable_source_link is true" do
      let(:config_with_source_link) do
        Broadlistening::Config.new(config_options.merge(enable_source_link: true))
      end
      let(:step_with_source_link) { described_class.new(config_with_source_link, context) }

      it "includes url when present" do
        step_with_source_link.execute
        result_h = context.result.to_h
        arg_with_url = result_h[:arguments].find { |a| a[:arg_id] == "A1_0" }
        expect(arg_with_url[:url]).to eq("https://example.com/comment/1")
      end

      it "does not include url key when not present" do
        step_with_source_link.execute
        result_h = context.result.to_h
        arg_without_url = result_h[:arguments].find { |a| a[:arg_id] == "A2_0" }
        expect(arg_without_url).not_to have_key(:url)
      end
    end

    context "when enable_source_link is false (default)" do
      it "does not include url even when present in argument" do
        step.execute
        result_h = context.result.to_h
        arg_with_url = result_h[:arguments].find { |a| a[:arg_id] == "A1_0" }
        expect(arg_with_url).not_to have_key(:url)
      end
    end
  end

  describe "is_pubcom CSV export" do
    let(:output_dir) { Dir.mktmpdir }
    let(:csv_path) { File.join(output_dir, "final_result_with_comments.csv") }

    after do
      FileUtils.rm_rf(output_dir)
    end

    before do
      context.output_dir = output_dir
    end

    context "when is_pubcom is true" do
      let(:config_with_pubcom) do
        Broadlistening::Config.new(config_options.merge(is_pubcom: true))
      end
      let(:step_with_pubcom) { described_class.new(config_with_pubcom, context) }

      it "exports CSV file" do
        step_with_pubcom.execute
        expect(File.exist?(csv_path)).to be true
      end

      it "includes correct headers" do
        step_with_pubcom.execute
        csv = CSV.read(csv_path, headers: true)
        expect(csv.headers).to include("comment_id", "original_comment", "arg_id", "argument", "category_id", "category", "x", "y")
      end

      it "includes all arguments in CSV" do
        step_with_pubcom.execute
        csv = CSV.read(csv_path, headers: true)
        expect(csv.size).to eq(3)
      end

      it "includes original comment body" do
        step_with_pubcom.execute
        csv = CSV.read(csv_path, headers: true)
        row = csv.find { |r| r["arg_id"] == "A1_0" }
        expect(row["original_comment"]).to eq("環境問題への対策が必要です")
      end

      it "includes category from level 1 cluster" do
        step_with_pubcom.execute
        csv = CSV.read(csv_path, headers: true)
        row = csv.find { |r| r["arg_id"] == "A1_0" }
        expect(row["category_id"]).to eq("1_0")
        expect(row["category"]).to eq("インフラ")
      end

      it "includes x and y coordinates" do
        step_with_pubcom.execute
        csv = CSV.read(csv_path, headers: true)
        row = csv.find { |r| r["arg_id"] == "A1_0" }
        expect(row["x"].to_f).to eq(0.5)
        expect(row["y"].to_f).to eq(0.3)
      end
    end

    context "when is_pubcom is true with attributes" do
      let(:config_with_pubcom) do
        Broadlistening::Config.new(config_options.merge(is_pubcom: true))
      end
      let(:step_with_pubcom) { described_class.new(config_with_pubcom, context) }

      let(:comments_with_attrs) do
        [
          Broadlistening::Comment.new(id: "1", body: "環境問題への対策が必要です", proposal_id: "123", attributes: { "age" => "30代", "region" => "東京" }),
          Broadlistening::Comment.new(id: "2", body: "公共交通機関の充実を希望します", proposal_id: "123"),
          Broadlistening::Comment.new(id: "3", body: "教育の質を向上させるべき", proposal_id: "123")
        ]
      end

      before do
        context.comments = comments_with_attrs
      end

      it "includes attribute columns in headers" do
        step_with_pubcom.execute
        csv = CSV.read(csv_path, headers: true)
        expect(csv.headers).to include("attribute_age", "attribute_region")
      end

      it "includes attribute values in rows" do
        step_with_pubcom.execute
        csv = CSV.read(csv_path, headers: true)
        row = csv.find { |r| r["arg_id"] == "A1_0" }
        expect(row["attribute_age"]).to eq("30代")
        expect(row["attribute_region"]).to eq("東京")
      end
    end

    context "when is_pubcom is false (default)" do
      it "does not export CSV file" do
        step.execute
        expect(File.exist?(csv_path)).to be false
      end
    end

    context "when output_dir is not set" do
      let(:config_with_pubcom) do
        Broadlistening::Config.new(config_options.merge(is_pubcom: true))
      end
      let(:step_with_pubcom) { described_class.new(config_with_pubcom, context) }

      before do
        context.output_dir = nil
      end

      it "does not export CSV file" do
        step_with_pubcom.execute
        expect(File.exist?(csv_path)).to be false
      end
    end
  end
end
