# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attributes and PropertyMap Compatibility" do
  # Test that attributes and propertyMap are handled correctly
  # when passing data through the pipeline

  let(:config_options) do
    {
      api_key: "test-api-key",
      model: "gpt-4o-mini",
      cluster_nums: [ 2, 5 ]
    }
  end

  let(:config) { Broadlistening::Config.new(config_options) }

  describe "Attributes pass-through" do
    describe "from Comment to Argument" do
      let(:comments) do
        [
          Broadlistening::Comment.new(
            id: "1",
            body: "Comment with attributes",
            proposal_id: "test",
            attributes: { "age" => "30代", "region" => "東京", "gender" => "male" },
            source_url: "https://example.com/comment/1"
          ),
          Broadlistening::Comment.new(
            id: "2",
            body: "Comment without attributes",
            proposal_id: "test",
            attributes: nil,
            source_url: nil
          ),
          Broadlistening::Comment.new(
            id: "3",
            body: "Comment with empty attributes",
            proposal_id: "test",
            attributes: {},
            source_url: "https://example.com/comment/3"
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
        allow(extraction_step).to receive(:extract_arguments_from_comment).and_return([ "Extracted opinion" ])
      end

      it "passes attributes from comment to argument" do
        extraction_step.execute
        arg = context.arguments.find { |a| a.arg_id == "A1_0" }

        expect(arg.attributes).to eq({ "age" => "30代", "region" => "東京", "gender" => "male" })
      end

      it "handles nil attributes" do
        extraction_step.execute
        arg = context.arguments.find { |a| a.arg_id == "A2_0" }

        expect(arg.attributes).to be_nil
      end

      it "handles empty attributes" do
        extraction_step.execute
        arg = context.arguments.find { |a| a.arg_id == "A3_0" }

        expect(arg.attributes).to eq({})
      end

      it "passes source_url as url" do
        extraction_step.execute
        arg = context.arguments.find { |a| a.arg_id == "A1_0" }

        expect(arg.url).to eq("https://example.com/comment/1")
      end

      it "handles nil source_url" do
        extraction_step.execute
        arg = context.arguments.find { |a| a.arg_id == "A2_0" }

        expect(arg.url).to be_nil
      end
    end
  end

  describe "Attributes in Aggregation output" do
    let(:arguments) do
      [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "Opinion 1",
          comment_id: "1",
          x: 0.5,
          y: 0.3,
          cluster_ids: %w[0 1_0 2_0],
          attributes: { "age" => "30代", "region" => "東京" }
        ),
        Broadlistening::Argument.new(
          arg_id: "A2_0",
          argument: "Opinion 2",
          comment_id: "2",
          x: 0.7,
          y: 0.2,
          cluster_ids: %w[0 1_0 2_1],
          attributes: nil
        ),
        Broadlistening::Argument.new(
          arg_id: "A3_0",
          argument: "Opinion 3",
          comment_id: "3",
          x: -0.3,
          y: 0.8,
          cluster_ids: %w[0 1_1 2_2],
          attributes: {}
        )
      ]
    end

    let(:comments) do
      [
        Broadlistening::Comment.new(id: "1", body: "Comment 1", proposal_id: "test"),
        Broadlistening::Comment.new(id: "2", body: "Comment 2", proposal_id: "test"),
        Broadlistening::Comment.new(id: "3", body: "Comment 3", proposal_id: "test")
      ]
    end

    let(:labels) do
      {
        "1_0" => Broadlistening::ClusterLabel.new(cluster_id: "1_0", level: 1, label: "Group A", description: "Description A"),
        "1_1" => Broadlistening::ClusterLabel.new(cluster_id: "1_1", level: 1, label: "Group B", description: "Description B"),
        "2_0" => Broadlistening::ClusterLabel.new(cluster_id: "2_0", level: 2, label: "Subgroup A1", description: "Sub A1"),
        "2_1" => Broadlistening::ClusterLabel.new(cluster_id: "2_1", level: 2, label: "Subgroup A2", description: "Sub A2"),
        "2_2" => Broadlistening::ClusterLabel.new(cluster_id: "2_2", level: 2, label: "Subgroup B1", description: "Sub B1")
      }
    end

    let(:cluster_results) do
      { 1 => [ 0, 0, 1 ], 2 => [ 0, 1, 2 ] }
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx.arguments = arguments
      ctx.labels = labels
      ctx.cluster_results = cluster_results
      ctx.overview = "Test overview"
      ctx
    end

    let(:aggregation_step) { Broadlistening::Steps::Aggregation.new(config, context) }

    let(:result) do
      aggregation_step.execute
      context.result.to_h
    end

    it "includes attributes in output arguments" do
      arg_with_attrs = result[:arguments].find { |a| a[:arg_id] == "A1_0" }
      expect(arg_with_attrs[:attributes]).to eq({ "age" => "30代", "region" => "東京" })
    end

    it "excludes attributes key for nil attributes" do
      arg_without_attrs = result[:arguments].find { |a| a[:arg_id] == "A2_0" }
      expect(arg_without_attrs).not_to have_key(:attributes)
    end

    it "includes empty attributes hash when attributes is empty" do
      # Note: Ruby implementation includes empty hash for attributes
      # This matches Python behavior where attributes key is always present
      arg_empty_attrs = result[:arguments].find { |a| a[:arg_id] == "A3_0" }
      expect(arg_empty_attrs[:attributes]).to eq({})
    end
  end

  describe "PropertyMap generation" do
    let(:config_with_properties) do
      Broadlistening::Config.new(config_options.merge(
        hidden_properties: {
          "source" => [ "hidden_source" ],
          "category" => []
        }
      ))
    end

    let(:arguments) do
      [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "Opinion 1",
          comment_id: "1",
          x: 0.5,
          y: 0.3,
          cluster_ids: %w[0 1_0],
          properties: { "source" => "twitter", "category" => "tech" }
        ),
        Broadlistening::Argument.new(
          arg_id: "A2_0",
          argument: "Opinion 2",
          comment_id: "2",
          x: 0.7,
          y: 0.2,
          cluster_ids: %w[0 1_0],
          properties: { "source" => "facebook", "category" => "politics" }
        ),
        Broadlistening::Argument.new(
          arg_id: "A3_0",
          argument: "Opinion 3",
          comment_id: "3",
          x: -0.3,
          y: 0.8,
          cluster_ids: %w[0 1_1],
          properties: nil
        )
      ]
    end

    let(:comments) do
      [
        Broadlistening::Comment.new(id: "1", body: "Comment 1", proposal_id: "test"),
        Broadlistening::Comment.new(id: "2", body: "Comment 2", proposal_id: "test"),
        Broadlistening::Comment.new(id: "3", body: "Comment 3", proposal_id: "test")
      ]
    end

    let(:labels) do
      {
        "1_0" => Broadlistening::ClusterLabel.new(cluster_id: "1_0", level: 1, label: "Group A", description: "Description A"),
        "1_1" => Broadlistening::ClusterLabel.new(cluster_id: "1_1", level: 1, label: "Group B", description: "Description B")
      }
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx.arguments = arguments
      ctx.labels = labels
      ctx.cluster_results = { 1 => [ 0, 0, 1 ] }
      ctx.overview = "Test overview"
      ctx
    end

    let(:aggregation_step) { Broadlistening::Steps::Aggregation.new(config_with_properties, context) }

    let(:result) do
      aggregation_step.execute
      context.result.to_h
    end

    it "builds propertyMap with property names as keys" do
      expect(result[:propertyMap].keys).to match_array(%w[source category])
    end

    it "maps arg_id to property values" do
      expect(result[:propertyMap]["source"]["A1_0"]).to eq("twitter")
      expect(result[:propertyMap]["source"]["A2_0"]).to eq("facebook")
    end

    it "does not include arguments without properties" do
      expect(result[:propertyMap]["source"]).not_to have_key("A3_0")
    end
  end

  describe "URL in output" do
    describe "when enable_source_link is true" do
      let(:config_with_source_link) do
        Broadlistening::Config.new(config_options.merge(enable_source_link: true))
      end

      let(:arguments) do
        [
          Broadlistening::Argument.new(
            arg_id: "A1_0",
            argument: "Opinion 1",
            comment_id: "1",
            x: 0.5,
            y: 0.3,
            cluster_ids: %w[0 1_0],
            url: "https://example.com/1"
          ),
          Broadlistening::Argument.new(
            arg_id: "A2_0",
            argument: "Opinion 2",
            comment_id: "2",
            x: 0.7,
            y: 0.2,
            cluster_ids: %w[0 1_0],
            url: nil
          )
        ]
      end

      let(:context) do
        ctx = Broadlistening::Context.new
        ctx.comments = [
          Broadlistening::Comment.new(id: "1", body: "Comment 1", proposal_id: "test"),
          Broadlistening::Comment.new(id: "2", body: "Comment 2", proposal_id: "test")
        ]
        ctx.arguments = arguments
        ctx.labels = { "1_0" => Broadlistening::ClusterLabel.new(cluster_id: "1_0", level: 1, label: "Group", description: "Desc") }
        ctx.cluster_results = { 1 => [ 0, 0 ] }
        ctx.overview = "Overview"
        ctx
      end

      let(:result) do
        step = Broadlistening::Steps::Aggregation.new(config_with_source_link, context)
        step.execute
        context.result.to_h
      end

      it "includes url when present" do
        arg_with_url = result[:arguments].find { |a| a[:arg_id] == "A1_0" }
        expect(arg_with_url[:url]).to eq("https://example.com/1")
      end

      it "excludes url key when nil" do
        arg_without_url = result[:arguments].find { |a| a[:arg_id] == "A2_0" }
        expect(arg_without_url).not_to have_key(:url)
      end
    end

    describe "when enable_source_link is false (default)" do
      let(:arguments) do
        [
          Broadlistening::Argument.new(
            arg_id: "A1_0",
            argument: "Opinion 1",
            comment_id: "1",
            x: 0.5,
            y: 0.3,
            cluster_ids: %w[0 1_0],
            url: "https://example.com/1"
          )
        ]
      end

      let(:context) do
        ctx = Broadlistening::Context.new
        ctx.comments = [ Broadlistening::Comment.new(id: "1", body: "Comment 1", proposal_id: "test") ]
        ctx.arguments = arguments
        ctx.labels = { "1_0" => Broadlistening::ClusterLabel.new(cluster_id: "1_0", level: 1, label: "Group", description: "Desc") }
        ctx.cluster_results = { 1 => [ 0 ] }
        ctx.overview = "Overview"
        ctx
      end

      let(:result) do
        step = Broadlistening::Steps::Aggregation.new(config, context)
        step.execute
        context.result.to_h
      end

      it "does not include url even when present in argument" do
        arg = result[:arguments].find { |a| a[:arg_id] == "A1_0" }
        expect(arg).not_to have_key(:url)
      end
    end
  end

  describe "properties pass-through" do
    let(:comments) do
      [
        Broadlistening::Comment.new(
          id: "1",
          body: "Comment with properties",
          proposal_id: "test",
          properties: { "source" => "twitter", "sentiment" => "positive" }
        ),
        Broadlistening::Comment.new(
          id: "2",
          body: "Comment without properties",
          proposal_id: "test",
          properties: nil
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
      allow(extraction_step).to receive(:extract_arguments_from_comment).and_return([ "Extracted opinion" ])
    end

    it "passes properties from comment to argument" do
      extraction_step.execute
      arg = context.arguments.find { |a| a.arg_id == "A1_0" }

      expect(arg.properties).to eq({ "source" => "twitter", "sentiment" => "positive" })
    end

    it "handles nil properties" do
      extraction_step.execute
      arg = context.arguments.find { |a| a.arg_id == "A2_0" }

      expect(arg.properties).to be_nil
    end
  end
end
