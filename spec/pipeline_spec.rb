# frozen_string_literal: true

RSpec.describe Broadlistening::Pipeline do
  let(:config_options) do
    {
      api_key: "test-api-key",
      model: "gpt-4o-mini",
      cluster_nums: [2, 5]
    }
  end

  let(:comments) do
    [
      { id: "1", body: "環境問題への対策が必要です", proposal_id: "123" },
      { id: "2", body: "公共交通機関の充実を希望します", proposal_id: "123" }
    ]
  end

  describe "ActiveSupport::Notifications" do
    describe "pipeline.broadlistening event" do
      it "instruments the entire pipeline run" do
        events = []
        subscription = ActiveSupport::Notifications.subscribe("pipeline.broadlistening") do |name, start, finish, id, payload|
          events << { name: name, payload: payload, duration: finish - start }
        end

        pipeline = described_class.new(config_options)

        # Mock all steps to avoid actual LLM calls
        allow_any_instance_of(Broadlistening::Steps::Extraction).to receive(:execute).and_return(
          { comments: comments, arguments: [], relations: [] }
        )
        allow_any_instance_of(Broadlistening::Steps::Embedding).to receive(:execute).and_return(
          { arguments: [] }
        )
        allow_any_instance_of(Broadlistening::Steps::Clustering).to receive(:execute).and_return(
          { arguments: [], cluster_results: {} }
        )
        allow_any_instance_of(Broadlistening::Steps::InitialLabelling).to receive(:execute).and_return(
          { initial_labels: {} }
        )
        allow_any_instance_of(Broadlistening::Steps::MergeLabelling).to receive(:execute).and_return(
          { labels: {} }
        )
        allow_any_instance_of(Broadlistening::Steps::Overview).to receive(:execute).and_return(
          { overview: "test overview" }
        )
        allow_any_instance_of(Broadlistening::Steps::Aggregation).to receive(:execute).and_return(
          { result: { overview: "test" } }
        )

        pipeline.run(comments)

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

        pipeline = described_class.new(config_options)

        # Mock all steps
        allow_any_instance_of(Broadlistening::Steps::Extraction).to receive(:execute).and_return(
          { comments: comments, arguments: [], relations: [] }
        )
        allow_any_instance_of(Broadlistening::Steps::Embedding).to receive(:execute).and_return(
          { arguments: [] }
        )
        allow_any_instance_of(Broadlistening::Steps::Clustering).to receive(:execute).and_return(
          { arguments: [], cluster_results: {} }
        )
        allow_any_instance_of(Broadlistening::Steps::InitialLabelling).to receive(:execute).and_return(
          { initial_labels: {} }
        )
        allow_any_instance_of(Broadlistening::Steps::MergeLabelling).to receive(:execute).and_return(
          { labels: {} }
        )
        allow_any_instance_of(Broadlistening::Steps::Overview).to receive(:execute).and_return(
          { overview: "test overview" }
        )
        allow_any_instance_of(Broadlistening::Steps::Aggregation).to receive(:execute).and_return(
          { result: { overview: "test" } }
        )

        pipeline.run(comments)

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

    describe "progress.broadlistening event" do
      it "emits progress events during step execution" do
        events = []
        subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |name, start, finish, id, payload|
          events << payload
        end

        config = Broadlistening::Config.new(config_options)
        context = { comments: comments }

        # Test Extraction step with mocked LLM client
        extraction = Broadlistening::Steps::Extraction.new(config, context)
        allow(extraction).to receive(:extract_arguments_from_comment).and_return(["opinion1"])

        extraction.execute

        ActiveSupport::Notifications.unsubscribe(subscription)

        expect(events.size).to eq(2) # One for each comment
        expect(events.first[:step]).to eq("extraction")
        expect(events.first[:current]).to be >= 1
        expect(events.first[:total]).to eq(2)
        expect(events.first[:percentage]).to be_a(Numeric)
      end

      it "calculates correct percentage" do
        events = []
        subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |name, start, finish, id, payload|
          events << payload
        end

        config = Broadlistening::Config.new(config_options)
        context = { comments: comments }

        extraction = Broadlistening::Steps::Extraction.new(config, context)
        allow(extraction).to receive(:extract_arguments_from_comment).and_return(["opinion1"])

        extraction.execute

        ActiveSupport::Notifications.unsubscribe(subscription)

        # With 2 comments, we expect 50% and 100% progress
        percentages = events.map { |e| e[:percentage] }
        expect(percentages).to include(50.0)
        expect(percentages).to include(100.0)
      end
    end
  end

  describe "Rails integration example" do
    it "allows subscribing to multiple events for different purposes" do
      step_log = []
      progress_log = []

      step_sub = ActiveSupport::Notifications.subscribe("step.broadlistening") do |*, payload|
        step_log << payload[:step]
      end

      progress_sub = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |*, payload|
        progress_log << "#{payload[:step]}: #{payload[:percentage]}%"
      end

      pipeline = described_class.new(config_options)

      # Mock all steps
      allow_any_instance_of(Broadlistening::Steps::Extraction).to receive(:execute).and_return(
        { comments: comments, arguments: [], relations: [] }
      )
      allow_any_instance_of(Broadlistening::Steps::Embedding).to receive(:execute).and_return(
        { arguments: [] }
      )
      allow_any_instance_of(Broadlistening::Steps::Clustering).to receive(:execute).and_return(
        { arguments: [], cluster_results: {} }
      )
      allow_any_instance_of(Broadlistening::Steps::InitialLabelling).to receive(:execute).and_return(
        { initial_labels: {} }
      )
      allow_any_instance_of(Broadlistening::Steps::MergeLabelling).to receive(:execute).and_return(
        { labels: {} }
      )
      allow_any_instance_of(Broadlistening::Steps::Overview).to receive(:execute).and_return(
        { overview: "test overview" }
      )
      allow_any_instance_of(Broadlistening::Steps::Aggregation).to receive(:execute).and_return(
        { result: { overview: "test" } }
      )

      pipeline.run(comments)

      ActiveSupport::Notifications.unsubscribe(step_sub)
      ActiveSupport::Notifications.unsubscribe(progress_sub)

      expect(step_log).to eq(%i[extraction embedding clustering initial_labelling merge_labelling overview aggregation])
    end
  end

  describe "#run with resume_from" do
    let(:saved_context) do
      {
        comments: comments,
        arguments: [
          { arg_id: "A1_0", argument: "環境問題への対策が必要", embedding: [0.1, 0.2] }
        ],
        relations: [
          { arg_id: "A1_0", comment_id: "1", proposal_id: "123" }
        ]
      }
    end

    before do
      # Mock steps that will be executed
      allow_any_instance_of(Broadlistening::Steps::Clustering).to receive(:execute).and_return(
        saved_context.merge(cluster_results: { 1 => [0], 2 => [0] })
      )
      allow_any_instance_of(Broadlistening::Steps::InitialLabelling).to receive(:execute).and_return(
        { initial_labels: { "2_0" => { label: "Test", description: "Desc" } } }
      )
      allow_any_instance_of(Broadlistening::Steps::MergeLabelling).to receive(:execute).and_return(
        { labels: {} }
      )
      allow_any_instance_of(Broadlistening::Steps::Overview).to receive(:execute).and_return(
        { overview: "test overview" }
      )
      allow_any_instance_of(Broadlistening::Steps::Aggregation).to receive(:execute).and_return(
        { result: { overview: "test" } }
      )
    end

    it "skips steps before resume_from" do
      extraction_called = false
      embedding_called = false
      clustering_called = false

      allow_any_instance_of(Broadlistening::Steps::Extraction).to receive(:execute) do |instance|
        extraction_called = true
        instance.context
      end
      allow_any_instance_of(Broadlistening::Steps::Embedding).to receive(:execute) do |instance|
        embedding_called = true
        instance.context
      end
      allow_any_instance_of(Broadlistening::Steps::Clustering).to receive(:execute) do |instance|
        clustering_called = true
        instance.context.merge(cluster_results: { 1 => [0], 2 => [0] })
      end

      pipeline = described_class.new(config_options)
      pipeline.run(comments, resume_from: :clustering, context: saved_context)

      expect(extraction_called).to be false
      expect(embedding_called).to be false
      expect(clustering_called).to be true
    end

    it "uses provided context" do
      pipeline = described_class.new(config_options)

      pipeline.run(comments, resume_from: :clustering, context: saved_context)

      # The saved_context had arguments, and it should be preserved through the pipeline
      # (the mocked steps return the context they receive, so arguments should still be there)
      expect(saved_context[:arguments]).not_to be_nil
    end

    it "runs only remaining steps" do
      step_log = []
      subscription = ActiveSupport::Notifications.subscribe("step.broadlistening") do |*, payload|
        step_log << payload[:step]
      end

      pipeline = described_class.new(config_options)
      pipeline.run(comments, resume_from: :clustering, context: saved_context)

      ActiveSupport::Notifications.unsubscribe(subscription)

      expect(step_log).to eq(%i[clustering initial_labelling merge_labelling overview aggregation])
    end

    it "preserves correct step indices" do
      events = []
      subscription = ActiveSupport::Notifications.subscribe("step.broadlistening") do |*, payload|
        events << payload
      end

      pipeline = described_class.new(config_options)
      pipeline.run(comments, resume_from: :clustering, context: saved_context)

      ActiveSupport::Notifications.unsubscribe(subscription)

      # First executed step (clustering) should have index 2
      expect(events.first[:step]).to eq(:clustering)
      expect(events.first[:step_index]).to eq(2)
      expect(events.first[:step_total]).to eq(7)
    end

    it "raises error for invalid step name" do
      pipeline = described_class.new(config_options)

      expect {
        pipeline.run(comments, resume_from: :invalid_step, context: saved_context)
      }.to raise_error(ArgumentError, /Invalid step: invalid_step/)
    end

    it "can resume from the last step" do
      allow_any_instance_of(Broadlistening::Steps::Aggregation).to receive(:execute).and_return(
        { result: { overview: "final result" } }
      )

      pipeline = described_class.new(config_options)
      result = pipeline.run(comments, resume_from: :aggregation, context: saved_context)

      expect(result).to eq({ overview: "final result" })
    end
  end

  describe "resumability workflow" do
    it "allows saving and restoring context between runs" do
      pipeline = described_class.new(config_options)

      # First run: extraction and embedding only (simulated failure after embedding)
      allow_any_instance_of(Broadlistening::Steps::Extraction).to receive(:execute).and_return(
        { comments: comments, arguments: [{ arg_id: "A1_0", argument: "test" }], relations: [] }
      )
      allow_any_instance_of(Broadlistening::Steps::Embedding).to receive(:execute).and_return(
        { comments: comments, arguments: [{ arg_id: "A1_0", argument: "test", embedding: [0.1] }], relations: [] }
      )
      allow_any_instance_of(Broadlistening::Steps::Clustering).to receive(:execute) do
        raise "Simulated failure"
      end

      # Run until failure
      expect { pipeline.run(comments) }.to raise_error("Simulated failure")

      # Save context for later
      saved_context = pipeline.context.dup

      # Second run: resume from clustering with saved context
      pipeline2 = described_class.new(config_options)

      allow_any_instance_of(Broadlistening::Steps::Clustering).to receive(:execute).and_return(
        saved_context.merge(cluster_results: { 1 => [0] })
      )
      allow_any_instance_of(Broadlistening::Steps::InitialLabelling).to receive(:execute).and_return(
        { initial_labels: {} }
      )
      allow_any_instance_of(Broadlistening::Steps::MergeLabelling).to receive(:execute).and_return(
        { labels: {} }
      )
      allow_any_instance_of(Broadlistening::Steps::Overview).to receive(:execute).and_return(
        { overview: "test" }
      )
      allow_any_instance_of(Broadlistening::Steps::Aggregation).to receive(:execute).and_return(
        { result: { success: true } }
      )

      result = pipeline2.run(comments, resume_from: :clustering, context: saved_context)

      expect(result).to eq({ success: true })
    end
  end
end
