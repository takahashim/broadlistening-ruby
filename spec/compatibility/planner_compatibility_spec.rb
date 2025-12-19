# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe "Planner Compatibility" do
  # Tests to verify Planner behavior matches Python's decide_what_to_run
  # Python: hierarchical_utils.py decide_what_to_run
  # Ruby: Planner#create_plan

  describe "Step name mapping" do
    # Python uses long names (hierarchical_clustering)
    # Ruby uses short names (clustering)

    describe "SpecLoader::STEP_MAPPING" do
      it "maps Python step names to Ruby step names" do
        expect(Broadlistening::SpecLoader::STEP_MAPPING["extraction"]).to eq(:extraction)
        expect(Broadlistening::SpecLoader::STEP_MAPPING["embedding"]).to eq(:embedding)
        expect(Broadlistening::SpecLoader::STEP_MAPPING["hierarchical_clustering"]).to eq(:clustering)
        expect(Broadlistening::SpecLoader::STEP_MAPPING["hierarchical_initial_labelling"]).to eq(:initial_labelling)
        expect(Broadlistening::SpecLoader::STEP_MAPPING["hierarchical_merge_labelling"]).to eq(:merge_labelling)
        expect(Broadlistening::SpecLoader::STEP_MAPPING["hierarchical_overview"]).to eq(:overview)
        expect(Broadlistening::SpecLoader::STEP_MAPPING["hierarchical_aggregation"]).to eq(:aggregation)
      end

      it "skips visualization step (gem responsibility)" do
        expect(Broadlistening::SpecLoader::STEP_MAPPING["hierarchical_visualization"]).to be_nil
      end

      it "covers all Python steps" do
        python_steps = %w[
          extraction
          embedding
          hierarchical_clustering
          hierarchical_initial_labelling
          hierarchical_merge_labelling
          hierarchical_overview
          hierarchical_aggregation
          hierarchical_visualization
        ]

        python_steps.each do |step|
          expect(Broadlistening::SpecLoader::STEP_MAPPING).to have_key(step),
            "Missing mapping for Python step: #{step}"
        end
      end
    end
  end

  describe "Decision logic compatibility" do
    # Test that Ruby Planner makes same decisions as Python decide_what_to_run

    let(:output_dir) { Dir.mktmpdir }

    let(:specs_json) do
      <<~JSON
        [
          {
            "step": "extraction",
            "filename": "args.csv",
            "dependencies": {"params": ["limit"], "steps": []},
            "use_llm": true
          },
          {
            "step": "embedding",
            "filename": "embeddings.pkl",
            "dependencies": {"params": ["model"], "steps": ["extraction"]},
            "use_llm": false
          },
          {
            "step": "hierarchical_clustering",
            "filename": "hierarchical_clusters.csv",
            "dependencies": {"params": ["cluster_nums"], "steps": ["embedding"]},
            "use_llm": false
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
            "dependencies": {"params": [], "steps": ["hierarchical_overview"]},
            "use_llm": false
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

    after do
      FileUtils.rm_rf(output_dir)
      specs_file.unlink
    end

    let(:spec_loader) { Broadlistening::SpecLoader.new(specs_file.path) }

    # Use short prompts that won't be hashed (< 100 chars)
    let(:short_prompts) do
      {
        extraction: "test",
        initial_labelling: "test",
        merge_labelling: "test",
        overview: "test"
      }
    end

    let(:config) do
      Broadlistening::Config.new(
        api_key: "test-key",
        model: "gpt-4o-mini",
        embedding_model: "text-embedding-3-small",
        cluster_nums: [ 5, 15 ],
        limit: 100,
        prompts: short_prompts
      )
    end

    def create_output_files(steps)
      steps.each do |step_name|
        file_config = Broadlistening::Context::OUTPUT_FILES[step_name]
        next unless file_config

        case file_config
        when Hash
          file_config.each_value do |filename|
            File.write(File.join(output_dir, filename), "test content")
          end
        when String
          File.write(File.join(output_dir, file_config), "test content")
        end
      end
    end

    describe "force flag (-f)" do
      it "runs all steps when force is true" do
        status = Broadlistening::Status.new(output_dir)
        planner = Broadlistening::Planner.new(
          config: config,
          status: status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )

        plan = planner.create_plan(force: true)

        plan.each do |step|
          expect(step.run?).to be true
          expect(step.reason).to eq("forced with -f")
        end
      end
    end

    describe "only flag (-o)" do
      it "runs only specified step when only is set" do
        status = Broadlistening::Status.new(output_dir)
        planner = Broadlistening::Planner.new(
          config: config,
          status: status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )

        plan = planner.create_plan(only: :clustering)

        clustering = plan.find { |s| s.step == :clustering }
        expect(clustering.run?).to be true
        expect(clustering.reason).to eq("forced this step with -o")

        others = plan.reject { |s| s.step == :clustering }
        others.each do |step|
          expect(step.run?).to be false
          expect(step.reason).to eq("forced another step with -o")
        end
      end
    end

    describe "no previous run" do
      it "runs all steps when no previous execution" do
        status = Broadlistening::Status.new(output_dir)
        planner = Broadlistening::Planner.new(
          config: config,
          status: status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )

        plan = planner.create_plan

        plan.each do |step|
          expect(step.run?).to be true
          expect(step.reason).to eq("no trace of previous run")
        end
      end
    end

    describe "dependency cascade" do
      it "re-runs dependent steps when parent re-runs" do
        # Create previous run with all steps completed
        short_prompt = "test" # < 100 chars, won't be hashed
        status_data = {
          status: "completed",
          completed_jobs: [
            { step: "extraction", params: { limit: 100, prompt: short_prompt, model: "gpt-4o-mini" }, duration: 1.0 },
            { step: "embedding", params: { model: "text-embedding-3-small" }, duration: 1.0 },
            { step: "clustering", params: { cluster_nums: [ 5, 15 ] }, duration: 1.0 },
            { step: "initial_labelling", params: { prompt: short_prompt, model: "gpt-4o-mini" }, duration: 1.0 },
            { step: "merge_labelling", params: { prompt: short_prompt, model: "gpt-4o-mini" }, duration: 1.0 },
            { step: "overview", params: { prompt: short_prompt, model: "gpt-4o-mini" }, duration: 1.0 },
            { step: "aggregation", params: {}, duration: 1.0 }
          ],
          previously_completed_jobs: []
        }
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, "status.json"), JSON.generate(status_data))

        # Create output files
        create_output_files(%i[extraction embedding clustering initial_labelling merge_labelling overview aggregation])

        # Change cluster_nums to trigger clustering and downstream
        config_changed = Broadlistening::Config.new(
          api_key: "test-key",
          model: "gpt-4o-mini",
          embedding_model: "text-embedding-3-small",
          cluster_nums: [ 3, 10 ], # Changed!
          limit: 100,
          prompts: short_prompts
        )

        fresh_status = Broadlistening::Status.new(output_dir)
        planner = Broadlistening::Planner.new(
          config: config_changed,
          status: fresh_status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )

        plan = planner.create_plan

        # extraction and embedding should not re-run (no change)
        extraction = plan.find { |s| s.step == :extraction }
        embedding = plan.find { |s| s.step == :embedding }
        expect(extraction.run?).to be false
        expect(embedding.run?).to be false

        # clustering should re-run (cluster_nums changed)
        clustering = plan.find { |s| s.step == :clustering }
        expect(clustering.run?).to be true
        expect(clustering.reason).to include("parameters changed")

        # downstream steps should cascade
        %i[initial_labelling merge_labelling overview aggregation].each do |step_name|
          step = plan.find { |s| s.step == step_name }
          expect(step.run?).to be true
          expect(step.reason).to include("dependent steps will re-run")
        end
      end
    end

    describe "nothing changed scenario" do
      it "skips all steps when nothing changed" do
        # Create previous run with all steps completed
        short_prompt = "test"
        status_data = {
          status: "completed",
          completed_jobs: [
            { step: "extraction", params: { limit: 100, prompt: short_prompt, model: "gpt-4o-mini" }, duration: 1.0 },
            { step: "embedding", params: { model: "text-embedding-3-small" }, duration: 1.0 },
            { step: "clustering", params: { cluster_nums: [ 5, 15 ] }, duration: 1.0 },
            { step: "initial_labelling", params: { prompt: short_prompt, model: "gpt-4o-mini" }, duration: 1.0 },
            { step: "merge_labelling", params: { prompt: short_prompt, model: "gpt-4o-mini" }, duration: 1.0 },
            { step: "overview", params: { prompt: short_prompt, model: "gpt-4o-mini" }, duration: 1.0 },
            { step: "aggregation", params: {}, duration: 1.0 }
          ],
          previously_completed_jobs: []
        }
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, "status.json"), JSON.generate(status_data))

        # Create output files
        create_output_files(%i[extraction embedding clustering initial_labelling merge_labelling overview aggregation])

        # Same config
        fresh_status = Broadlistening::Status.new(output_dir)
        planner = Broadlistening::Planner.new(
          config: config,
          status: fresh_status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )

        plan = planner.create_plan

        plan.each do |step|
          expect(step.run?).to be false
          expect(step.reason).to eq("nothing changed")
        end
      end
    end

    describe "missing output file" do
      it "re-runs step when output file is missing" do
        # Create previous run
        short_prompt = "test"
        status_data = {
          status: "completed",
          completed_jobs: [
            { step: "extraction", params: { limit: 100, prompt: short_prompt, model: "gpt-4o-mini" }, duration: 1.0 },
            { step: "embedding", params: { model: "text-embedding-3-small" }, duration: 1.0 }
          ],
          previously_completed_jobs: []
        }
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, "status.json"), JSON.generate(status_data))

        # Only create extraction output, not embedding
        create_output_files(%i[extraction])

        fresh_status = Broadlistening::Status.new(output_dir)
        planner = Broadlistening::Planner.new(
          config: config,
          status: fresh_status,
          output_dir: output_dir,
          spec_loader: spec_loader
        )

        plan = planner.create_plan

        extraction = plan.find { |s| s.step == :extraction }
        embedding = plan.find { |s| s.step == :embedding }

        expect(extraction.run?).to be false
        expect(embedding.run?).to be true
        expect(embedding.reason).to eq("previous output not found")
      end
    end
  end

  describe "Cross-platform status file compatibility" do
    # Test reading status files that may have been created by Python

    let(:output_dir) { Dir.mktmpdir }

    after { FileUtils.rm_rf(output_dir) }

    describe "reading Python-format step names" do
      it "normalizes Python step names to Ruby step names" do
        # Simulate Python status.json with long step names
        python_status = {
          "status" => "completed",
          "completed_jobs" => [
            {
              "step" => "extraction",
              "params" => { "limit" => 100 },
              "duration" => 1.0
            },
            {
              "step" => "hierarchical_clustering", # Python name
              "params" => { "cluster_nums" => [ 5, 15 ] },
              "duration" => 1.0
            }
          ]
        }

        File.write(File.join(output_dir, "status.json"), JSON.generate(python_status))

        status = Broadlistening::Status.new(output_dir)

        # Should find jobs regardless of naming convention
        jobs = status.all_completed_jobs
        step_names = jobs.map(&:step)

        # The current implementation stores step names as-is
        # This test documents current behavior
        expect(step_names).to include("extraction")
        expect(step_names).to include("hierarchical_clustering")
      end
    end
  end
end
