# frozen_string_literal: true

RSpec.describe "Step Notifications" do
  let(:config_options) do
    {
      api_key: "test-api-key",
      model: "gpt-4o-mini",
      cluster_nums: [ 2, 5 ],
      workers: 1 # Use single worker to ensure sequential processing in tests
    }
  end

  let(:config) { Broadlistening::Config.new(config_options) }

  after do
    ActiveSupport::Notifications.unsubscribe(@subscription) if @subscription
  end

  describe Broadlistening::Steps::Extraction do
    let(:comments) do
      [
        Broadlistening::Comment.new(id: "1", body: "コメント1", proposal_id: "123"),
        Broadlistening::Comment.new(id: "2", body: "コメント2", proposal_id: "123"),
        Broadlistening::Comment.new(id: "3", body: "コメント3", proposal_id: "123")
      ]
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx
    end

    it "emits progress events for each comment processed" do
      events = []
      @subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |*, payload|
        events << payload
      end

      step = described_class.new(config, context)
      allow(step).to receive(:extract_arguments_from_comment).and_return([ "opinion" ])

      step.execute

      expect(events.size).to eq(3)
      expect(events.map { |e| e[:step] }).to all(eq("extraction"))
      expect(events.last[:current]).to eq(3)
      expect(events.last[:total]).to eq(3)
      expect(events.last[:percentage]).to eq(100.0)
    end

    it "includes correct percentage calculations" do
      events = []
      @subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |*, payload|
        events << payload
      end

      step = described_class.new(config, context)
      allow(step).to receive(:extract_arguments_from_comment).and_return([ "opinion" ])

      step.execute

      # Due to parallel processing, order may vary, but all percentages should be present
      percentages = events.map { |e| e[:percentage] }.sort
      expect(percentages).to eq([ 33.3, 66.7, 100.0 ])
    end
  end

  describe Broadlistening::Steps::Embedding do
    let(:arguments) do
      [
        Broadlistening::Argument.new(arg_id: "A1_0", argument: "意見1", comment_id: "1"),
        Broadlistening::Argument.new(arg_id: "A2_0", argument: "意見2", comment_id: "2")
      ]
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.arguments = arguments
      ctx
    end

    it "emits progress events for each batch" do
      events = []
      @subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |*, payload|
        events << payload
      end

      step = described_class.new(config, context)

      mock_client = instance_double(Broadlistening::LlmClient)
      allow(step).to receive(:llm_client).and_return(mock_client)
      allow(mock_client).to receive(:embed).and_return([ [ 0.1, 0.2 ], [ 0.3, 0.4 ] ])

      step.execute

      expect(events.size).to eq(1) # One batch for 2 arguments (batch size is 1000)
      expect(events.first[:step]).to eq("embedding")
      expect(events.first[:percentage]).to eq(100.0)
    end
  end

  describe Broadlistening::Steps::InitialLabelling do
    let(:arguments) do
      [
        Broadlistening::Argument.new(arg_id: "A1_0", argument: "意見1", comment_id: "1", cluster_ids: %w[0 1_0 2_0]),
        Broadlistening::Argument.new(arg_id: "A2_0", argument: "意見2", comment_id: "2", cluster_ids: %w[0 1_0 2_1]),
        Broadlistening::Argument.new(arg_id: "A3_0", argument: "意見3", comment_id: "3", cluster_ids: %w[0 1_1 2_2])
      ]
    end

    let(:cluster_results) do
      {
        1 => [ 0, 0, 1 ],
        2 => [ 0, 1, 2 ]
      }
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.arguments = arguments
      ctx.cluster_results = cluster_results
      ctx
    end

    it "emits progress events for each cluster labeled" do
      events = []
      @subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |*, payload|
        events << payload
      end

      step = described_class.new(config, context)

      mock_client = instance_double(Broadlistening::LlmClient)
      allow(step).to receive(:llm_client).and_return(mock_client)
      allow(mock_client).to receive(:chat).and_return('{"label": "Test", "description": "Test desc"}')

      step.execute

      expect(events.size).to eq(3) # 3 clusters at max level
      expect(events.map { |e| e[:step] }).to all(eq("initial_labelling"))
    end
  end

  describe Broadlistening::Steps::MergeLabelling do
    let(:arguments) do
      [
        Broadlistening::Argument.new(arg_id: "A1_0", argument: "意見1", comment_id: "1", cluster_ids: %w[0 1_0 2_0]),
        Broadlistening::Argument.new(arg_id: "A2_0", argument: "意見2", comment_id: "2", cluster_ids: %w[0 1_0 2_1]),
        Broadlistening::Argument.new(arg_id: "A3_0", argument: "意見3", comment_id: "3", cluster_ids: %w[0 1_1 2_2])
      ]
    end

    let(:cluster_results) do
      {
        1 => [ 0, 0, 1 ],
        2 => [ 0, 1, 2 ]
      }
    end

    let(:initial_labels) do
      {
        "2_0" => Broadlistening::ClusterLabel.new(cluster_id: "2_0", level: 2, label: "Label0", description: "Desc0"),
        "2_1" => Broadlistening::ClusterLabel.new(cluster_id: "2_1", level: 2, label: "Label1", description: "Desc1"),
        "2_2" => Broadlistening::ClusterLabel.new(cluster_id: "2_2", level: 2, label: "Label2", description: "Desc2")
      }
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.arguments = arguments
      ctx.cluster_results = cluster_results
      ctx.initial_labels = initial_labels
      ctx
    end

    it "emits progress events with level information" do
      events = []
      @subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |*, payload|
        events << payload
      end

      step = described_class.new(config, context)

      mock_client = instance_double(Broadlistening::LlmClient)
      allow(step).to receive(:llm_client).and_return(mock_client)
      allow(mock_client).to receive(:chat).and_return('{"label": "Merged", "description": "Merged desc"}')

      step.execute

      expect(events.size).to eq(2) # 2 clusters at level 1
      expect(events.map { |e| e[:step] }).to all(eq("merge_labelling"))
      expect(events.first[:message]).to eq("level 1")
    end
  end

  describe Broadlistening::Steps::BaseStep do
    # Define a named test class to avoid nil class name issues
    class TestStep < Broadlistening::Steps::BaseStep
      attr_accessor :test_params

      def execute
        notify_progress(**test_params)
        context
      end
    end

    let(:context) { Broadlistening::Context.new }

    describe "#notify_progress" do
      it "handles zero total gracefully" do
        events = []
        @subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |*, payload|
          events << payload
        end

        step = TestStep.new(config, context)
        step.test_params = { current: 0, total: 0 }
        step.execute

        expect(events.first[:percentage]).to eq(0)
      end

      it "includes optional message in payload" do
        events = []
        @subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |*, payload|
          events << payload
        end

        step = TestStep.new(config, context)
        step.test_params = { current: 1, total: 2, message: "processing batch 1" }
        step.execute

        expect(events.first[:message]).to eq("processing batch 1")
      end

      it "calculates percentage correctly" do
        events = []
        @subscription = ActiveSupport::Notifications.subscribe("progress.broadlistening") do |*, payload|
          events << payload
        end

        step = TestStep.new(config, context)
        step.test_params = { current: 3, total: 4 }
        step.execute

        expect(events.first[:percentage]).to eq(75.0)
        expect(events.first[:step]).to eq("test_step")
      end
    end
  end
end
