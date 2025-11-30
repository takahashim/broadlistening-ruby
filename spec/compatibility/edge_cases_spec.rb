# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Edge Cases Compatibility" do
  let(:config_options) do
    {
      api_key: "test-api-key",
      model: "gpt-4o-mini",
      cluster_nums: [ 2, 5 ]
    }
  end

  let(:config) { Broadlistening::Config.new(config_options) }

  describe "Single comment input" do
    let(:comments) do
      [
        Broadlistening::Comment.new(
          id: "1",
          body: "This is the only comment",
          proposal_id: "test"
        )
      ]
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx
    end

    let(:extraction_step) { Broadlistening::Steps::Extraction.new(config, context) }

    before do
      allow(extraction_step).to receive(:extract_arguments_from_comment).and_return([ "Single opinion" ])
    end

    it "handles single comment extraction" do
      extraction_step.execute

      expect(context.arguments.size).to eq(1)
      expect(context.arguments.first.arg_id).to eq("A1_0")
    end
  end

  describe "Empty comments input" do
    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = []
      ctx
    end

    let(:extraction_step) { Broadlistening::Steps::Extraction.new(config, context) }

    it "handles empty comments array" do
      extraction_step.execute

      expect(context.arguments).to be_empty
    end
  end

  describe "Comments with special characters" do
    let(:comments) do
      [
        Broadlistening::Comment.new(
          id: "1",
          body: "Comment with <html> tags & \"quotes\" and 'apostrophes'",
          proposal_id: "test"
        ),
        Broadlistening::Comment.new(
          id: "2",
          body: "Comment with unicode: 日本語テスト 🎉 emoji",
          proposal_id: "test"
        ),
        Broadlistening::Comment.new(
          id: "3",
          body: "Comment with newlines\nand\ttabs",
          proposal_id: "test"
        )
      ]
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx
    end

    let(:extraction_step) { Broadlistening::Steps::Extraction.new(config, context) }

    before do
      allow(extraction_step).to receive(:extract_arguments_from_comment)
        .and_return([ "Extracted text" ])
    end

    it "handles HTML entities" do
      extraction_step.execute

      expect(context.arguments.find { |a| a.arg_id == "A1_0" }).not_to be_nil
    end

    it "handles unicode and emoji" do
      extraction_step.execute

      expect(context.arguments.find { |a| a.arg_id == "A2_0" }).not_to be_nil
    end

    it "handles whitespace characters" do
      extraction_step.execute

      expect(context.arguments.find { |a| a.arg_id == "A3_0" }).not_to be_nil
    end
  end

  describe "Very long comments" do
    let(:long_text) { "A" * 10_000 }

    let(:comments) do
      [
        Broadlistening::Comment.new(
          id: "1",
          body: long_text,
          proposal_id: "test"
        )
      ]
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx
    end

    let(:extraction_step) { Broadlistening::Steps::Extraction.new(config, context) }

    before do
      allow(extraction_step).to receive(:extract_arguments_from_comment)
        .and_return([ "Long opinion summary" ])
    end

    it "handles very long comment body" do
      extraction_step.execute

      expect(context.arguments.size).to eq(1)
    end
  end

  describe "cluster_nums larger than argument count" do
    let(:small_config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 10, 50 ] # Larger than we'll have arguments
      )
    end

    let(:arguments) do
      5.times.map do |i|
        Broadlistening::Argument.new(
          arg_id: "A#{i}_0",
          argument: "Opinion #{i}",
          comment_id: i.to_s,
          embedding: Array.new(1536) { rand }
        )
      end
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.arguments = arguments
      ctx
    end

    let(:clustering_step) { Broadlistening::Steps::Clustering.new(small_config, context) }

    it "adjusts cluster_nums to not exceed argument count" do
      clustering_step.execute

      # Should produce at most as many clusters as there are arguments
      max_clusters = context.arguments.flat_map(&:cluster_ids).uniq.size
      expect(max_clusters).to be <= 5 + 1 # +1 for root
    end

    it "produces valid cluster assignments" do
      clustering_step.execute

      context.arguments.each do |arg|
        expect(arg.cluster_ids).to include("0") # Root cluster
        expect(arg.cluster_ids.size).to be >= 2 # At least root + one level
      end
    end
  end

  describe "Minimum cluster_nums" do
    let(:min_config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 1, 2 ]
      )
    end

    let(:arguments) do
      10.times.map do |i|
        Broadlistening::Argument.new(
          arg_id: "A#{i}_0",
          argument: "Opinion #{i}",
          comment_id: i.to_s,
          embedding: Array.new(1536) { rand }
        )
      end
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.arguments = arguments
      ctx
    end

    let(:clustering_step) { Broadlistening::Steps::Clustering.new(min_config, context) }

    it "handles minimal cluster configuration" do
      clustering_step.execute

      # Should have root + 2 levels
      first_arg = context.arguments.first
      expect(first_arg.cluster_ids.size).to eq(3) # root + level1 + level2
    end
  end

  describe "Multiple opinions from single comment" do
    let(:comments) do
      [
        Broadlistening::Comment.new(
          id: "1",
          body: "I think X. Also, Y is important. Furthermore, Z.",
          proposal_id: "test"
        )
      ]
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx
    end

    let(:extraction_step) { Broadlistening::Steps::Extraction.new(config, context) }

    before do
      allow(extraction_step).to receive(:extract_arguments_from_comment)
        .and_return([ "Opinion about X", "Opinion about Y", "Opinion about Z" ])
    end

    it "creates multiple arguments with sequential indices" do
      extraction_step.execute

      expect(context.arguments.size).to eq(3)
      expect(context.arguments.map(&:arg_id)).to eq([ "A1_0", "A1_1", "A1_2" ])
    end

    it "all arguments reference same comment_id" do
      extraction_step.execute

      context.arguments.each do |arg|
        expect(arg.comment_id).to eq("1")
      end
    end
  end

  describe "Numeric comment IDs" do
    let(:comments) do
      [
        Broadlistening::Comment.new(id: 123, body: "Comment 123", proposal_id: "test"),
        Broadlistening::Comment.new(id: "456", body: "Comment 456", proposal_id: "test")
      ]
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx
    end

    let(:extraction_step) { Broadlistening::Steps::Extraction.new(config, context) }

    before do
      allow(extraction_step).to receive(:extract_arguments_from_comment)
        .and_return([ "Opinion" ])
    end

    it "handles integer comment IDs" do
      extraction_step.execute

      arg = context.arguments.find { |a| a.arg_id == "A123_0" }
      expect(arg).not_to be_nil
    end

    it "handles string comment IDs" do
      extraction_step.execute

      arg = context.arguments.find { |a| a.arg_id == "A456_0" }
      expect(arg).not_to be_nil
    end
  end

  describe "JSON serialization edge cases" do
    let(:arguments) do
      [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "Normal opinion",
          comment_id: "1",
          x: 1.23456789012345,
          y: -9.87654321098765,
          cluster_ids: %w[0 1_0]
        ),
        Broadlistening::Argument.new(
          arg_id: "A2_0",
          argument: "Opinion with \"quotes\"",
          comment_id: "2",
          x: 0.0,
          y: 0.0,
          cluster_ids: %w[0 1_0]
        )
      ]
    end

    let(:labels) do
      {
        "1_0" => Broadlistening::ClusterLabel.new(
          cluster_id: "1_0",
          level: 1,
          label: "Label with \"special\" chars",
          description: "Description with\nnewlines"
        )
      }
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = [
        Broadlistening::Comment.new(id: "1", body: "Comment 1", proposal_id: "test"),
        Broadlistening::Comment.new(id: "2", body: "Comment 2", proposal_id: "test")
      ]
      ctx.arguments = arguments
      ctx.labels = labels
      ctx.cluster_results = { 1 => [ 0, 0 ] }
      ctx.overview = "Overview with\ttabs and\nnewlines"
      ctx
    end

    let(:aggregation_step) { Broadlistening::Steps::Aggregation.new(config, context) }

    it "produces valid JSON with special characters" do
      aggregation_step.execute

      json_string = JSON.generate(context.result.to_h)
      expect { JSON.parse(json_string) }.not_to raise_error
    end

    it "preserves floating point precision" do
      aggregation_step.execute

      result_h = context.result.to_h
      arg = result_h[:arguments].first
      expect(arg[:x]).to be_a(Float)
      expect(arg[:y]).to be_a(Float)
    end
  end

  describe "Empty extraction result" do
    let(:comments) do
      [
        Broadlistening::Comment.new(
          id: "1",
          body: "Comment that yields no opinions",
          proposal_id: "test"
        )
      ]
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx
    end

    let(:extraction_step) { Broadlistening::Steps::Extraction.new(config, context) }

    before do
      allow(extraction_step).to receive(:extract_arguments_from_comment)
        .and_return([]) # No opinions extracted
    end

    it "handles comments with no extracted opinions" do
      extraction_step.execute

      expect(context.arguments).to be_empty
    end
  end
end
