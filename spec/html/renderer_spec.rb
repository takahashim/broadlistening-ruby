# frozen_string_literal: true

require "tmpdir"
require "tempfile"

RSpec.describe Broadlistening::Html::Renderer do
  let(:arguments) do
    [
      Broadlistening::PipelineResult::Argument.new(
        arg_id: "A1_0",
        argument: "We need more parks",
        comment_id: 1,
        x: 0.5,
        y: -0.3,
        p: 0,
        cluster_ids: %w[0 1_0 2_1],
        attributes: nil,
        url: nil
      ),
      Broadlistening::PipelineResult::Argument.new(
        arg_id: "A2_0",
        argument: "Better public transport",
        comment_id: 2,
        x: 1.2,
        y: 0.8,
        p: 0,
        cluster_ids: %w[0 1_1 2_3],
        attributes: nil,
        url: nil
      )
    ]
  end

  let(:clusters) do
    [
      Broadlistening::PipelineResult::Cluster.root(2),
      Broadlistening::PipelineResult::Cluster.new(
        level: 1,
        id: "1_0",
        label: "Environment",
        takeaway: "Concerns about parks and green spaces",
        value: 1,
        parent: "0",
        density_rank_percentile: nil
      ),
      Broadlistening::PipelineResult::Cluster.new(
        level: 1,
        id: "1_1",
        label: "Transportation",
        takeaway: "Issues with public transit",
        value: 1,
        parent: "0",
        density_rank_percentile: nil
      )
    ]
  end

  let(:result) do
    Broadlistening::PipelineResult.new(
      arguments: arguments,
      clusters: clusters,
      comments: {
        "1" => Broadlistening::PipelineResult::Comment.new(comment: "Original comment 1"),
        "2" => Broadlistening::PipelineResult::Comment.new(comment: "Original comment 2")
      },
      property_map: {},
      translations: {},
      overview: "This is an overview of all the feedback.",
      config: { model: "gpt-4o-mini" },
      comment_num: 2
    )
  end

  describe "#initialize" do
    it "accepts a PipelineResult" do
      renderer = described_class.new(result)
      expect(renderer.result).to eq(result)
    end

    it "uses default title when not specified" do
      renderer = described_class.new(result)
      expect(renderer.title).to eq("分析結果")
    end

    it "accepts custom title" do
      renderer = described_class.new(result, title: "My Report")
      expect(renderer.title).to eq("My Report")
    end
  end

  describe "#level1_clusters" do
    it "returns only level 1 clusters" do
      renderer = described_class.new(result)
      expect(renderer.level1_clusters.size).to eq(2)
      expect(renderer.level1_clusters.all? { |c| c.level == 1 }).to be true
    end

    it "sorts by value descending" do
      renderer = described_class.new(result)
      values = renderer.level1_clusters.map(&:value)
      expect(values).to eq(values.sort.reverse)
    end
  end

  describe "#cluster_color" do
    it "returns a color for valid cluster ID" do
      renderer = described_class.new(result)
      expect(renderer.cluster_color("1_0")).to eq("#1f77b4")
      expect(renderer.cluster_color("1_1")).to eq("#ff7f0e")
    end

    it "returns first color for invalid cluster ID" do
      renderer = described_class.new(result)
      expect(renderer.cluster_color(nil)).to eq("#1f77b4")
      expect(renderer.cluster_color("invalid")).to eq("#1f77b4")
    end
  end

  describe "#points_json" do
    it "generates valid JSON" do
      renderer = described_class.new(result)
      json = renderer.points_json
      parsed = JSON.parse(json)

      expect(parsed).to be_an(Array)
      expect(parsed.size).to eq(2)
      expect(parsed.first).to include("arg_id", "argument", "x", "y", "cluster_id")
    end
  end

  describe "#cluster_meta_json" do
    it "generates valid JSON with cluster metadata" do
      renderer = described_class.new(result)
      json = renderer.cluster_meta_json
      parsed = JSON.parse(json)

      expect(parsed).to be_a(Hash)
      expect(parsed.keys).to include("1_0", "1_1")
      expect(parsed["1_0"]).to include("label" => "Environment", "color" => "#1f77b4")
    end
  end

  describe "#render" do
    it "generates HTML" do
      renderer = described_class.new(result)
      html = renderer.render

      expect(html).to include("<!DOCTYPE html>")
      expect(html).to include("<html lang=\"ja\">")
      expect(html).to include("Plotly")
    end

    it "includes the title" do
      renderer = described_class.new(result, title: "Test Report")
      html = renderer.render

      expect(html).to include("<title>Test Report</title>")
      expect(html).to include("Test Report")
    end

    it "includes the overview" do
      renderer = described_class.new(result)
      html = renderer.render

      expect(html).to include("This is an overview of all the feedback.")
    end

    it "includes cluster labels" do
      renderer = described_class.new(result)
      html = renderer.render

      expect(html).to include("Environment")
      expect(html).to include("Transportation")
    end

    it "includes comment count" do
      renderer = described_class.new(result)
      html = renderer.render

      expect(html).to include("2件")
    end
  end

  describe "#save" do
    it "writes HTML to file" do
      renderer = described_class.new(result)
      path = File.join(Dir.tmpdir, "test_report_#{Time.now.to_i}.html")

      begin
        renderer.save(path)
        expect(File.exist?(path)).to be true
        expect(File.read(path)).to include("<!DOCTYPE html>")
      ensure
        File.delete(path) if File.exist?(path)
      end
    end
  end

  describe ".from_json" do
    let(:json_data) do
      {
        arguments: [
          {
            arg_id: "A1_0",
            argument: "Test argument",
            comment_id: 1,
            x: 0.5,
            y: -0.3,
            p: 0,
            cluster_ids: %w[0 1_0],
            attributes: nil,
            url: nil
          }
        ],
        clusters: [
          { level: 0, id: "0", label: "Root", takeaway: "", value: 1, parent: "", density_rank_percentile: nil },
          { level: 1, id: "1_0", label: "Cluster 1", takeaway: "Description", value: 1, parent: "0",
            density_rank_percentile: nil }
        ],
        comments: { "1" => { comment: "Original comment" } },
        propertyMap: {},
        translations: {},
        overview: "Test overview",
        config: { model: "test" },
        comment_num: 1
      }
    end

    it "loads from JSON file" do
      Tempfile.create([ "test", ".json" ]) do |f|
        f.write(JSON.generate(json_data))
        f.flush

        renderer = described_class.from_json(f.path)
        expect(renderer.result.arguments.size).to eq(1)
        expect(renderer.result.clusters.size).to eq(2)
        expect(renderer.result.overview).to eq("Test overview")
      end
    end

    it "accepts options" do
      Tempfile.create([ "test", ".json" ]) do |f|
        f.write(JSON.generate(json_data))
        f.flush

        renderer = described_class.from_json(f.path, title: "Custom Title")
        expect(renderer.title).to eq("Custom Title")
      end
    end

    it "generates valid HTML" do
      Tempfile.create([ "test", ".json" ]) do |f|
        f.write(JSON.generate(json_data))
        f.flush

        renderer = described_class.from_json(f.path)
        html = renderer.render
        expect(html).to include("<!DOCTYPE html>")
        expect(html).to include("Test overview")
        expect(html).to include("Cluster 1")
      end
    end
  end

  describe ".build_result_from_json" do
    it "handles missing optional fields" do
      data = {
        arguments: [],
        clusters: [],
        overview: "Test"
      }

      result = described_class.build_result_from_json(data)
      expect(result.arguments).to eq([])
      expect(result.clusters).to eq([])
      expect(result.comments).to eq({})
      expect(result.overview).to eq("Test")
    end
  end
end
