# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe Broadlistening::Planner do
  # Helper to create output files matching Context::OUTPUT_FILES format
  def create_output_files_for_planner_test(dir)
    Broadlistening::Context::OUTPUT_FILES.each do |_step, file_config|
      case file_config
      when Hash
        # Multiple files (e.g., extraction)
        file_config.each_value do |filename|
          File.write(File.join(dir, filename), "arg-id,argument\nA1_0,test")
        end
      when String
        if file_config.end_with?('.csv')
          File.write(File.join(dir, file_config), "header\nvalue")
        elsif file_config.end_with?('.txt')
          File.write(File.join(dir, file_config), "test content")
        else
          File.write(File.join(dir, file_config), '{}')
        end
      end
    end
  end

  let(:output_dir) { Dir.mktmpdir }
  let(:config) do
    Broadlistening::Config.new(
      api_key: 'test-key',
      model: 'gpt-4o-mini',
      embedding_model: 'text-embedding-3-small',
      cluster_nums: [ 5, 15 ]
    )
  end
  let(:status) { Broadlistening::Status.new(output_dir) }
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
    file = Tempfile.new([ 'specs', '.json' ])
    file.write(specs_json)
    file.close
    file
  end
  let(:spec_loader) { Broadlistening::SpecLoader.new(specs_file.path) }

  after do
    FileUtils.rm_rf(output_dir)
    specs_file.unlink
  end

  subject(:planner) do
    described_class.new(
      config: config,
      status: status,
      output_dir: output_dir,
      spec_loader: spec_loader
    )
  end

  describe '#create_plan' do
    context 'when no previous run exists' do
      it 'plans to run all steps' do
        plan = planner.create_plan
        expect(plan.all? { |p| p[:run] }).to be true
      end

      it "gives reason 'no trace of previous run'" do
        plan = planner.create_plan
        expect(plan.first[:reason]).to eq('no trace of previous run')
      end
    end

    context 'when force is true' do
      let(:completed_jobs_data) do
        spec_loader.steps.map do |step|
          { step: step.to_s, completed: '2024-01-01T00:00:00Z', duration: 1.0, params: {}, token_usage: 0 }
        end
      end

      before do
        # Create status file with completed jobs
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'status.json'), {
          status: 'completed',
          completed_jobs: completed_jobs_data
        }.to_json)
        # Create output files using Context::OUTPUT_FILES format
        create_output_files_for_planner_test(output_dir)
      end

      let(:fresh_status) { Broadlistening::Status.new(output_dir) }
      let(:planner_for_test) do
        described_class.new(
          config: config,
          status: fresh_status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )
      end

      it 'plans to run all steps' do
        plan = planner_for_test.create_plan(force: true)
        expect(plan.all? { |p| p[:run] }).to be true
      end

      it "gives reason 'forced with -f'" do
        plan = planner_for_test.create_plan(force: true)
        expect(plan.first[:reason]).to eq('forced with -f')
      end
    end

    context 'when only is specified' do
      let(:completed_jobs_data) do
        spec_loader.steps.map do |step|
          { step: step.to_s, completed: '2024-01-01T00:00:00Z', duration: 1.0, params: {}, token_usage: 0 }
        end
      end

      before do
        # Create status file with completed jobs
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'status.json'), {
          status: 'completed',
          completed_jobs: completed_jobs_data
        }.to_json)
        # Create output files using Context::OUTPUT_FILES format
        create_output_files_for_planner_test(output_dir)
      end

      let(:fresh_status) { Broadlistening::Status.new(output_dir) }
      let(:planner_for_test) do
        described_class.new(
          config: config,
          status: fresh_status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )
      end

      it 'plans to run only the specified step' do
        plan = planner_for_test.create_plan(only: :clustering)
        running_steps = plan.select { |p| p[:run] }.map { |p| p[:step] }
        expect(running_steps).to eq([ :clustering ])
      end

      it "gives reason 'forced this step with -o'" do
        plan = planner_for_test.create_plan(only: :clustering)
        clustering_plan = plan.find { |p| p[:step] == :clustering }
        expect(clustering_plan[:reason]).to eq('forced this step with -o')
      end

      it "gives reason 'forced another step with -o' for other steps" do
        plan = planner_for_test.create_plan(only: :clustering)
        extraction_plan = plan.find { |p| p[:step] == :extraction }
        expect(extraction_plan[:reason]).to eq('forced another step with -o')
      end
    end

    context 'when output file is missing' do
      let(:completed_jobs_data) do
        spec_loader.steps.map do |step|
          { step: step.to_s, completed: '2024-01-01T00:00:00Z', duration: 1.0, params: {}, token_usage: 0 }
        end
      end

      before do
        # Create status file with completed jobs
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'status.json'), {
          status: 'completed',
          completed_jobs: completed_jobs_data
        }.to_json)
        # Create output files except extraction (to test missing output detection)
        Broadlistening::Context::OUTPUT_FILES.each do |step, file_config|
          next if step == :extraction

          case file_config
          when Hash
            file_config.each_value do |filename|
              File.write(File.join(output_dir, filename), "arg-id,argument\nA1_0,test")
            end
          when String
            if file_config.end_with?('.csv')
              File.write(File.join(output_dir, file_config), "header\nvalue")
            elsif file_config.end_with?('.txt')
              File.write(File.join(output_dir, file_config), "test content")
            else
              File.write(File.join(output_dir, file_config), '{}')
            end
          end
        end
      end

      let(:fresh_status) { Broadlistening::Status.new(output_dir) }
      let(:planner_for_test) do
        described_class.new(
          config: config,
          status: fresh_status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )
      end

      it 'plans to re-run step with missing output' do
        plan = planner_for_test.create_plan
        extraction_plan = plan.find { |p| p[:step] == :extraction }
        expect(extraction_plan[:run]).to be true
        expect(extraction_plan[:reason]).to eq('previous output not found')
      end

      it 'plans to re-run dependent steps' do
        plan = planner_for_test.create_plan
        embedding_plan = plan.find { |p| p[:step] == :embedding }
        expect(embedding_plan[:run]).to be true
        expect(embedding_plan[:reason]).to include('dependent steps will re-run')
      end
    end

    context 'when nothing changed' do
      # Need to create planner first, then modify status, then create a new planner
      let(:completed_jobs_data) do
        spec_loader.steps.map do |step|
          params = described_class.new(
            config: config,
            status: status,
            output_dir: output_dir,
            spec_loader: spec_loader
          ).extract_current_params(step)
          serialized_params = params.transform_values do |v|
            v.is_a?(String) && v.length > 100 ? Digest::SHA256.hexdigest(v) : v
          end
          { step: step.to_s, completed: '2024-01-01T00:00:00Z', duration: 1.0, params: serialized_params, token_usage: 0 }
        end
      end

      before do
        # Simulate previous run with current params by writing to status file
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'status.json'), {
          status: 'completed',
          completed_jobs: completed_jobs_data
        }.to_json)
        # Create output files using Context::OUTPUT_FILES (CSV/TXT/JSON format)
        create_output_files_for_planner_test(output_dir)
      end

      # Create a fresh planner that reads the saved status
      let(:planner_for_test) do
        fresh_status = Broadlistening::Status.new(output_dir)
        described_class.new(
          config: config,
          status: fresh_status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )
      end

      it 'plans to skip all steps' do
        plan = planner_for_test.create_plan
        expect(plan.all? { |p| !p[:run] }).to be true
      end

      it "gives reason 'nothing changed'" do
        plan = planner_for_test.create_plan
        expect(plan.first[:reason]).to eq('nothing changed')
      end
    end

    context 'when parameter changed' do
      let(:completed_jobs_data) do
        [
          { step: 'extraction', completed: '2024-01-01T00:00:00Z', duration: 1.0, token_usage: 0,
            params: { model: 'gpt-4o-mini', prompt: Digest::SHA256.hexdigest(config.prompts[:extraction]) } },
          { step: 'embedding', completed: '2024-01-01T00:00:00Z', duration: 1.0, token_usage: 0,
            params: { model: 'text-embedding-3-small' } },
          { step: 'clustering', completed: '2024-01-01T00:00:00Z', duration: 1.0, token_usage: 0,
            params: { cluster_nums: [ 3, 6 ] } }, # Different from current [5, 15]
          { step: 'initial_labelling', completed: '2024-01-01T00:00:00Z', duration: 1.0, token_usage: 0,
            params: { model: 'gpt-4o-mini', prompt: Digest::SHA256.hexdigest(config.prompts[:initial_labelling]) } },
          { step: 'merge_labelling', completed: '2024-01-01T00:00:00Z', duration: 1.0, token_usage: 0,
            params: { model: 'gpt-4o-mini', prompt: Digest::SHA256.hexdigest(config.prompts[:merge_labelling]) } },
          { step: 'overview', completed: '2024-01-01T00:00:00Z', duration: 1.0, token_usage: 0,
            params: { model: 'gpt-4o-mini', prompt: Digest::SHA256.hexdigest(config.prompts[:overview]) } },
          { step: 'aggregation', completed: '2024-01-01T00:00:00Z', duration: 1.0, token_usage: 0,
            params: {} }
        ]
      end

      before do
        # Simulate previous run with different cluster_nums by writing to status file
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'status.json'), {
          status: 'completed',
          completed_jobs: completed_jobs_data
        }.to_json)
        # Create output files using Context::OUTPUT_FILES format
        create_output_files_for_planner_test(output_dir)
      end

      let(:fresh_status) { Broadlistening::Status.new(output_dir) }
      let(:planner_for_test) do
        described_class.new(
          config: config,
          status: fresh_status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )
      end

      it 'plans to re-run step with changed parameter' do
        plan = planner_for_test.create_plan
        clustering_plan = plan.find { |p| p[:step] == :clustering }
        expect(clustering_plan[:run]).to be true
        expect(clustering_plan[:reason]).to include('parameters changed')
      end

      it 'plans to re-run dependent steps' do
        plan = planner_for_test.create_plan
        initial_labelling_plan = plan.find { |p| p[:step] == :initial_labelling }
        expect(initial_labelling_plan[:run]).to be true
        expect(initial_labelling_plan[:reason]).to include('dependent steps will re-run')
      end

      it 'does not re-run independent steps' do
        plan = planner_for_test.create_plan
        extraction_plan = plan.find { |p| p[:step] == :extraction }
        embedding_plan = plan.find { |p| p[:step] == :embedding }
        expect(extraction_plan[:run]).to be false
        expect(embedding_plan[:run]).to be false
      end
    end
  end

  describe '#extract_current_params' do
    it 'returns model and prompt for extraction' do
      params = planner.extract_current_params(:extraction)
      expect(params[:model]).to eq('gpt-4o-mini')
      expect(params[:prompt]).to be_a(String)
    end

    it 'returns model (embedding_model) for embedding' do
      # Python specs.json uses 'model' as the param name for embedding step
      params = planner.extract_current_params(:embedding)
      expect(params[:model]).to eq('text-embedding-3-small')
    end

    it 'returns cluster_nums for clustering' do
      params = planner.extract_current_params(:clustering)
      expect(params[:cluster_nums]).to eq([ 5, 15 ])
    end

    it 'returns empty hash for aggregation' do
      params = planner.extract_current_params(:aggregation)
      expect(params).to eq({})
    end
  end
end
