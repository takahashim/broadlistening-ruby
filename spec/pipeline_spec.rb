# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Broadlistening::Pipeline do
  let(:output_dir) { Dir.mktmpdir }
  let(:config_options) do
    {
      api_key: "test-api-key",
      model: "gpt-4o-mini",
      cluster_nums: [ 2, 5 ]
    }
  end

  let(:comments) do
    [
      { id: "1", body: "環境問題への対策が必要です", proposal_id: "123" },
      { id: "2", body: "公共交通機関の充実を希望します", proposal_id: "123" }
    ]
  end

  let(:specs_json) do
    <<~JSON
      [
        {
          "step": "extraction",
          "filename": "args.csv",
          "dependencies": {"params": [], "steps": []},
          "use_llm": true
        },
        {
          "step": "embedding",
          "filename": "embeddings.pkl",
          "dependencies": {"params": ["model"], "steps": ["extraction"]}
        },
        {
          "step": "hierarchical_clustering",
          "filename": "hierarchical_clusters.csv",
          "dependencies": {"params": ["cluster_nums"], "steps": ["embedding"]}
        },
        {
          "step": "hierarchical_initial_labelling",
          "filename": "hierarchical_initial_labels.csv",
          "dependencies": {"params": [], "steps": ["hierarchical_clustering"]},
          "use_llm": true
        },
        {
          "step": "hierarchical_merge_labelling",
          "filename": "hierarchical_merge_labels.csv",
          "dependencies": {"params": [], "steps": ["hierarchical_initial_labelling"]},
          "use_llm": true
        },
        {
          "step": "hierarchical_overview",
          "filename": "hierarchical_overview.txt",
          "dependencies": {"params": [], "steps": ["hierarchical_merge_labelling"]},
          "use_llm": true
        },
        {
          "step": "hierarchical_aggregation",
          "filename": "hierarchical_result.json",
          "dependencies": {"params": [], "steps": ["hierarchical_overview"]}
        }
      ]
    JSON
  end

  let(:specs_file) do
    file = Tempfile.new([ "specs", ".json" ])
    file.write(specs_json)
    file.close
    file
  end

  let(:spec_loader) { Broadlistening::SpecLoader.new(specs_file.path) }

  after do
    FileUtils.rm_rf(output_dir)
    specs_file.unlink
  end

  def mock_all_steps
    allow_any_instance_of(Broadlistening::Steps::Extraction).to receive(:execute) do |step|
      step.context.arguments = [
        Broadlistening::Argument.new(arg_id: "A1_0", argument: "test", comment_id: "1")
      ]
      step.context.relations = [{ arg_id: "A1_0", comment_id: "1" }]
      step.context
    end
    allow_any_instance_of(Broadlistening::Steps::Embedding).to receive(:execute) do |step|
      step.context.arguments.each { |a| a.embedding = [0.1, 0.2] }
      step.context
    end
    allow_any_instance_of(Broadlistening::Steps::Clustering).to receive(:execute) do |step|
      step.context.arguments.each do |a|
        a.x = 0.5
        a.y = 0.5
        a.cluster_ids = ["0", "1_0"]
      end
      step.context.cluster_results = { 1 => [0] }
      step.context
    end
    allow_any_instance_of(Broadlistening::Steps::InitialLabelling).to receive(:execute) do |step|
      step.context.initial_labels = {
        "1_0" => Broadlistening::ClusterLabel.new(cluster_id: "1_0", level: 1, label: "Test", description: "Desc")
      }
      step.context
    end
    allow_any_instance_of(Broadlistening::Steps::MergeLabelling).to receive(:execute) do |step|
      step.context.labels = {
        "0" => Broadlistening::ClusterLabel.new(cluster_id: "0", level: 0, label: "All", description: "All opinions"),
        "1_0" => Broadlistening::ClusterLabel.new(cluster_id: "1_0", level: 1, label: "Test", description: "Desc")
      }
      step.context
    end
    allow_any_instance_of(Broadlistening::Steps::Overview).to receive(:execute) do |step|
      step.context.instance_variable_set(:@overview, "test overview")
      step.context
    end
    allow_any_instance_of(Broadlistening::Steps::Aggregation).to receive(:execute) do |step|
      step.context.result = Broadlistening::PipelineResult.new(
        arguments: step.context.arguments.map do |arg|
          Broadlistening::PipelineResult::Argument.new(
            arg_id: arg.arg_id,
            argument: arg.argument,
            comment_id: arg.comment_id.to_i,
            x: arg.x,
            y: arg.y,
            p: 0,
            cluster_ids: arg.cluster_ids || [],
            attributes: {},
            url: nil
          )
        end,
        clusters: [Broadlistening::PipelineResult::Cluster.root(step.context.arguments.size)],
        comments: {},
        property_map: {},
        translations: {},
        overview: "test overview",
        config: {},
        comment_num: step.context.arguments.size
      )
      step.context
    end
  end

  describe "#run with incremental execution" do
    it "runs all steps on first execution" do
      mock_all_steps

      step_log = []
      subscription = ActiveSupport::Notifications.subscribe("step.broadlistening") do |*, payload|
        step_log << payload[:step]
      end

      pipeline = described_class.new(config_options, spec_loader: spec_loader)
      pipeline.run(comments, output_dir: output_dir)

      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(step_log).to eq(%i[extraction embedding clustering initial_labelling merge_labelling overview aggregation])
    end

    it "creates status.json file" do
      mock_all_steps

      pipeline = described_class.new(config_options, spec_loader: spec_loader)
      pipeline.run(comments, output_dir: output_dir)

      expect(File.exist?(File.join(output_dir, "status.json"))).to be true
    end

    it "creates intermediate output files" do
      mock_all_steps

      pipeline = described_class.new(config_options, spec_loader: spec_loader)
      pipeline.run(comments, output_dir: output_dir)

      # CSV format for extraction (args.csv + relations.csv)
      expect(File.exist?(File.join(output_dir, "args.csv"))).to be true
      expect(File.exist?(File.join(output_dir, "relations.csv"))).to be true
      # JSON format for embedding (kept as JSON)
      expect(File.exist?(File.join(output_dir, "embeddings.json"))).to be true
      # CSV format for clustering
      expect(File.exist?(File.join(output_dir, "hierarchical_clusters.csv"))).to be true
      # JSON format for final result
      expect(File.exist?(File.join(output_dir, "hierarchical_result.json"))).to be true
    end

    it "skips steps when nothing changed" do
      mock_all_steps

      # First run
      pipeline1 = described_class.new(config_options, spec_loader: spec_loader)
      pipeline1.run(comments, output_dir: output_dir)

      # Second run - should skip all steps
      step_log = []
      skip_log = []

      step_sub = ActiveSupport::Notifications.subscribe("step.broadlistening") do |*, payload|
        step_log << payload[:step]
      end
      skip_sub = ActiveSupport::Notifications.subscribe("step.skip.broadlistening") do |*, payload|
        skip_log << payload[:step]
      end

      pipeline2 = described_class.new(config_options, spec_loader: spec_loader)
      pipeline2.run(comments, output_dir: output_dir)

      ActiveSupport::Notifications.unsubscribe(step_sub)
      ActiveSupport::Notifications.unsubscribe(skip_sub)

      expect(step_log).to be_empty
      expect(skip_log.size).to eq(7)
    end

    it "re-runs dependent steps when output file is deleted" do
      mock_all_steps

      # First run
      pipeline1 = described_class.new(config_options, spec_loader: spec_loader)
      pipeline1.run(comments, output_dir: output_dir)

      # Delete clustering output
      FileUtils.rm(File.join(output_dir, "hierarchical_clusters.csv"))

      # Second run - should re-run clustering and dependent steps
      step_log = []
      subscription = ActiveSupport::Notifications.subscribe("step.broadlistening") do |*, payload|
        step_log << payload[:step]
      end

      pipeline2 = described_class.new(config_options, spec_loader: spec_loader)
      pipeline2.run(comments, output_dir: output_dir)

      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(step_log).to include(:clustering)
      expect(step_log).to include(:initial_labelling)
      expect(step_log).not_to include(:extraction)
      expect(step_log).not_to include(:embedding)
    end

    it "re-runs all steps with force: true" do
      mock_all_steps

      # First run
      pipeline1 = described_class.new(config_options, spec_loader: spec_loader)
      pipeline1.run(comments, output_dir: output_dir)

      # Second run with force
      step_log = []
      subscription = ActiveSupport::Notifications.subscribe("step.broadlistening") do |*, payload|
        step_log << payload[:step]
      end

      pipeline2 = described_class.new(config_options, spec_loader: spec_loader)
      pipeline2.run(comments, output_dir: output_dir, force: true)

      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(step_log.size).to eq(7)
    end

    it "runs only specified step with only: option" do
      mock_all_steps

      # First run
      pipeline1 = described_class.new(config_options, spec_loader: spec_loader)
      pipeline1.run(comments, output_dir: output_dir)

      # Second run with only: :aggregation
      step_log = []
      subscription = ActiveSupport::Notifications.subscribe("step.broadlistening") do |*, payload|
        step_log << payload[:step]
      end

      pipeline2 = described_class.new(config_options, spec_loader: spec_loader)
      pipeline2.run(comments, output_dir: output_dir, only: :aggregation)

      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(step_log).to eq([ :aggregation ])
    end

    it "raises error when pipeline is locked" do
      mock_all_steps

      # Create a locked status
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, "status.json"), {
        status: "running",
        lock_until: (Time.now + 300).iso8601
      }.to_json)

      pipeline = described_class.new(config_options, spec_loader: spec_loader)

      expect {
        pipeline.run(comments, output_dir: output_dir)
      }.to raise_error(Broadlistening::Error, /locked/)
    end

    it "allows running when lock has expired" do
      mock_all_steps

      # Create an expired lock
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, "status.json"), {
        status: "running",
        lock_until: (Time.now - 60).iso8601
      }.to_json)

      pipeline = described_class.new(config_options, spec_loader: spec_loader)

      expect {
        pipeline.run(comments, output_dir: output_dir)
      }.not_to raise_error
    end

    it "records error status on failure" do
      allow_any_instance_of(Broadlistening::Steps::Extraction).to receive(:execute) do
        raise StandardError, "Test error"
      end

      pipeline = described_class.new(config_options, spec_loader: spec_loader)

      expect {
        pipeline.run(comments, output_dir: output_dir)
      }.to raise_error(StandardError, "Test error")

      status = JSON.parse(File.read(File.join(output_dir, "status.json")))
      expect(status["status"]).to eq("error")
      expect(status["error"]).to include("Test error")
    end
  end

  describe "ActiveSupport::Notifications" do
    describe "pipeline.broadlistening event" do
      it "instruments the entire pipeline run" do
        events = []
        subscription = ActiveSupport::Notifications.subscribe("pipeline.broadlistening") do |name, start, finish, id, payload|
          events << { name: name, payload: payload, duration: finish - start }
        end

        mock_all_steps

        pipeline = described_class.new(config_options, spec_loader: spec_loader)
        pipeline.run(comments, output_dir: output_dir)

        ActiveSupport::Notifications.unsubscribe(subscription)

        expect(events.size).to eq(1)
        expect(events.first[:name]).to eq("pipeline.broadlistening")
        expect(events.first[:payload][:comment_count]).to eq(2)
        expect(events.first[:duration]).to be >= 0
      end
    end

    describe "step.broadlistening event" do
      it "instruments each pipeline step" do
        events = []
        subscription = ActiveSupport::Notifications.subscribe("step.broadlistening") do |name, start, finish, id, payload|
          events << { name: name, payload: payload, duration: finish - start }
        end

        mock_all_steps

        pipeline = described_class.new(config_options, spec_loader: spec_loader)
        pipeline.run(comments, output_dir: output_dir)

        ActiveSupport::Notifications.unsubscribe(subscription)

        expect(events.size).to eq(7)

        # Check first step
        expect(events.first[:payload][:step]).to eq(:extraction)
        expect(events.first[:payload][:step_index]).to eq(0)
        expect(events.first[:payload][:step_total]).to eq(7)

        # Check last step
        expect(events.last[:payload][:step]).to eq(:aggregation)
        expect(events.last[:payload][:step_index]).to eq(6)
        expect(events.last[:payload][:step_total]).to eq(7)

        # All steps should have duration
        events.each do |event|
          expect(event[:duration]).to be >= 0
        end
      end
    end

    describe "step.skip.broadlistening event" do
      it "emits skip events for skipped steps" do
        mock_all_steps

        # First run
        pipeline1 = described_class.new(config_options, spec_loader: spec_loader)
        pipeline1.run(comments, output_dir: output_dir)

        # Second run - capture skip events
        skip_events = []
        subscription = ActiveSupport::Notifications.subscribe("step.skip.broadlistening") do |*, payload|
          skip_events << payload
        end

        pipeline2 = described_class.new(config_options, spec_loader: spec_loader)
        pipeline2.run(comments, output_dir: output_dir)

        ActiveSupport::Notifications.unsubscribe(subscription)

        expect(skip_events.size).to eq(7)
        expect(skip_events.first[:step]).to eq(:extraction)
        expect(skip_events.first[:reason]).to eq("nothing changed")
      end
    end

    describe "progress.broadlistening event" do
      it "emits progress events during step execution" do
        events = []
        subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |name, start, finish, id, payload|
          events << payload
        end

        config = Broadlistening::Config.new(config_options)
        context = Broadlistening::Context.new
        context.comments = comments.map do |c|
          Broadlistening::Comment.new(id: c[:id], body: c[:body], proposal_id: c[:proposal_id])
        end

        # Test Extraction step with mocked LLM client
        extraction = Broadlistening::Steps::Extraction.new(config, context)
        allow(extraction).to receive(:extract_arguments_from_comment).and_return([ "opinion1" ])

        extraction.execute

        ActiveSupport::Notifications.unsubscribe(subscription)

        expect(events.size).to eq(2) # One for each comment
        expect(events.first[:step]).to eq("extraction")
        expect(events.first[:current]).to be >= 1
        expect(events.first[:total]).to eq(2)
        expect(events.first[:percentage]).to be_a(Numeric)
      end
    end
  end

  describe "#normalize_comments" do
    let(:pipeline) { described_class.new(config_options, spec_loader: spec_loader) }

    describe "attributes extraction" do
      it "extracts attribute_* fields from hash comments" do
        comments_with_attrs = [
          {
            id: "1",
            body: "Test comment",
            attribute_age: "30代",
            attribute_region: "東京"
          }
        ]

        normalized = pipeline.send(:normalize_comments, comments_with_attrs)

        expect(normalized.first).to be_a(Broadlistening::Comment)
        expect(normalized.first.attributes).to eq({ "age" => "30代", "region" => "東京" })
      end

      it "extracts attribute-* fields (hyphen style) from hash comments" do
        comments_with_attrs = [
          {
            id: "1",
            body: "Test comment",
            "attribute-age" => "40代",
            "attribute-region" => "大阪"
          }
        ]

        normalized = pipeline.send(:normalize_comments, comments_with_attrs)

        expect(normalized.first.attributes).to eq({ "age" => "40代", "region" => "大阪" })
      end

      it "returns nil for attributes when no attribute fields exist" do
        comments_without_attrs = [
          { id: "1", body: "Test comment" }
        ]

        normalized = pipeline.send(:normalize_comments, comments_without_attrs)

        expect(normalized.first.attributes).to be_nil
      end
    end

    describe "source_url extraction" do
      it "extracts source_url from hash comments" do
        comments_with_url = [
          {
            id: "1",
            body: "Test comment",
            source_url: "https://example.com/1"
          }
        ]

        normalized = pipeline.send(:normalize_comments, comments_with_url)

        expect(normalized.first.source_url).to eq("https://example.com/1")
      end

      it "extracts source-url (hyphen style) from hash comments" do
        comments_with_url = [
          {
            id: "1",
            body: "Test comment",
            "source-url" => "https://example.com/2"
          }
        ]

        normalized = pipeline.send(:normalize_comments, comments_with_url)

        expect(normalized.first.source_url).to eq("https://example.com/2")
      end
    end

    describe "properties extraction" do
      let(:config_with_properties) do
        {
          api_key: "test-api-key",
          model: "gpt-4o-mini",
          cluster_nums: [ 2, 5 ],
          hidden_properties: {
            "source" => [ "X API" ],
            "age" => [ 20, 25 ]
          }
        }
      end
      let(:pipeline_with_properties) { described_class.new(config_with_properties, spec_loader: spec_loader) }

      it "extracts properties based on hidden_properties config" do
        comments_with_props = [
          {
            id: "1",
            body: "Test comment",
            source: "twitter",
            age: 35
          }
        ]

        normalized = pipeline_with_properties.send(:normalize_comments, comments_with_props)

        expect(normalized.first.properties).to eq({ "source" => "twitter", "age" => 35 })
      end
    end
  end
end
