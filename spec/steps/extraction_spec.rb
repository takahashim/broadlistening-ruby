# frozen_string_literal: true

RSpec.describe Broadlistening::Steps::Extraction do
  let(:config_options) do
    {
      api_key: "test-api-key",
      model: "gpt-4o-mini",
      cluster_nums: [ 2, 5 ]
    }
  end

  let(:config) { Broadlistening::Config.new(config_options) }

  describe "attributes and url pass-through" do
    let(:comments) do
      [
        Broadlistening::Comment.new(
          id: "1",
          body: "環境問題への対策が必要です",
          proposal_id: "123",
          attributes: { "age" => "30代", "region" => "東京" },
          source_url: "https://example.com/comment/1"
        ),
        Broadlistening::Comment.new(
          id: "2",
          body: "公共交通機関の充実を希望します",
          proposal_id: "123",
          attributes: nil,
          source_url: nil
        )
      ]
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx
    end

    subject(:step) { described_class.new(config, context) }

    before do
      # Mock LLM to return simple opinions
      allow(step).to receive(:extract_arguments_from_comment).and_return([ "抽出された意見" ])
    end

    it "passes attributes from comment to argument" do
      step.execute
      arg_with_attrs = context.arguments.find { |a| a.arg_id == "A1_0" }

      expect(arg_with_attrs.attributes).to eq({ "age" => "30代", "region" => "東京" })
    end

    it "passes source_url as url from comment to argument" do
      step.execute
      arg_with_url = context.arguments.find { |a| a.arg_id == "A1_0" }

      expect(arg_with_url.url).to eq("https://example.com/comment/1")
    end

    it "sets attributes to nil when not present in comment" do
      step.execute
      arg_without_attrs = context.arguments.find { |a| a.arg_id == "A2_0" }

      expect(arg_without_attrs.attributes).to be_nil
    end

    it "sets url to nil when source_url is nil" do
      step.execute
      arg_without_url = context.arguments.find { |a| a.arg_id == "A2_0" }

      expect(arg_without_url.url).to be_nil
    end

    it "passes properties from comment to argument" do
      comments_with_properties = [
        Broadlistening::Comment.new(
          id: "1",
          body: "環境問題への対策が必要です",
          proposal_id: "123",
          properties: { "source" => "twitter", "age" => 35 }
        ),
        Broadlistening::Comment.new(
          id: "2",
          body: "公共交通機関の充実を希望します",
          proposal_id: "123",
          properties: nil
        )
      ]

      context_with_properties = Broadlistening::Context.new
      context_with_properties.comments = comments_with_properties

      step_with_properties = described_class.new(config, context_with_properties)
      allow(step_with_properties).to receive(:extract_arguments_from_comment).and_return([ "抽出された意見" ])

      step_with_properties.execute

      arg_with_props = context_with_properties.arguments.find { |a| a.arg_id == "A1_0" }
      expect(arg_with_props.properties).to eq({ "source" => "twitter", "age" => 35 })

      arg_without_props = context_with_properties.arguments.find { |a| a.arg_id == "A2_0" }
      expect(arg_without_props.properties).to be_nil
    end
  end
end
