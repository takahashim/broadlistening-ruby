# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe "Status File Compatibility" do
  # Tests to verify Status file format matches Python's hierarchical_status.json
  # Python: hierarchical_utils.py update_status, run_step, termination
  # Ruby: Status class

  let(:output_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(output_dir) }

  describe "Reading Python-format status files" do
    # Python writes to hierarchical_status.json with specific structure
    # Ruby should be able to read and understand this format

    describe "completed pipeline status" do
      before do
        python_status = {
          "status" => "completed",
          "plan" => [
            { "step" => "extraction", "run" => true, "reason" => "no trace of previous run" },
            { "step" => "embedding", "run" => true, "reason" => "no trace of previous run" },
            { "step" => "hierarchical_clustering", "run" => true, "reason" => "no trace of previous run" }
          ],
          "start_time" => "2024-01-01T10:00:00+09:00",
          "end_time" => "2024-01-01T10:30:00+09:00",
          "lock_until" => "2024-01-01T10:35:00+09:00",
          "completed_jobs" => [
            {
              "step" => "extraction",
              "completed" => "2024-01-01T10:10:00+09:00",
              "duration" => 600.5,
              "params" => { "limit" => 1000, "prompt" => "Extract opinions", "model" => "gpt-4o-mini" },
              "token_usage" => 15000
            },
            {
              "step" => "embedding",
              "completed" => "2024-01-01T10:15:00+09:00",
              "duration" => 300.2,
              "params" => { "model" => "text-embedding-3-small" },
              "token_usage" => 0
            },
            {
              "step" => "hierarchical_clustering",
              "completed" => "2024-01-01T10:20:00+09:00",
              "duration" => 120.0,
              "params" => { "cluster_nums" => [ 5, 15 ] },
              "token_usage" => 0
            }
          ],
          "previously_completed_jobs" => [],
          "total_token_usage" => 15000,
          "token_usage_input" => 10000,
          "token_usage_output" => 5000,
          "provider" => "openai",
          "model" => "gpt-4o-mini"
        }

        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, "status.json"), JSON.generate(python_status))
      end

      let(:status) { Broadlistening::Status.new(output_dir) }

      it "reads completed_jobs correctly" do
        jobs = status.all_completed_jobs
        expect(jobs.size).to eq(3)
      end

      it "preserves step names" do
        jobs = status.all_completed_jobs
        expect(jobs.map(&:step)).to eq(%w[extraction embedding hierarchical_clustering])
      end

      it "preserves params" do
        extraction_job = status.all_completed_jobs.find { |j| j.step == "extraction" }
        expect(extraction_job.params[:limit]).to eq(1000)
        expect(extraction_job.params[:model]).to eq("gpt-4o-mini")
      end

      it "preserves duration" do
        extraction_job = status.all_completed_jobs.find { |j| j.step == "extraction" }
        expect(extraction_job.duration).to eq(600.5)
      end

      it "is not locked (completed status)" do
        expect(status.locked?).to be false
      end
    end

    describe "running pipeline status with lock" do
      before do
        python_status = {
          "status" => "running",
          "lock_until" => (Time.now + 300).iso8601,
          "current_job" => "embedding",
          "current_job_started" => Time.now.iso8601,
          "completed_jobs" => [
            {
              "step" => "extraction",
              "completed" => Time.now.iso8601,
              "duration" => 100.0,
              "params" => {},
              "token_usage" => 0
            }
          ],
          "previously_completed_jobs" => []
        }

        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, "status.json"), JSON.generate(python_status))
      end

      let(:status) { Broadlistening::Status.new(output_dir) }

      it "detects locked status" do
        expect(status.locked?).to be true
      end
    end

    describe "error status" do
      before do
        python_status = {
          "status" => "error",
          "error" => "ValueError: some error occurred",
          "error_stack_trace" => "Traceback (most recent call last):\n  File ...",
          "end_time" => "2024-01-01T10:30:00+09:00",
          "completed_jobs" => [],
          "previously_completed_jobs" => []
        }

        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, "status.json"), JSON.generate(python_status))
      end

      let(:status) { Broadlistening::Status.new(output_dir) }

      it "reads error status" do
        expect(status.locked?).to be false
      end
    end

    describe "previously_completed_jobs handling" do
      # Python preserves jobs from previous runs in previously_completed_jobs
      before do
        python_status = {
          "status" => "completed",
          "completed_jobs" => [
            {
              "step" => "hierarchical_clustering",
              "completed" => "2024-01-02T10:00:00+09:00",
              "duration" => 50.0,
              "params" => { "cluster_nums" => [ 3, 10 ] },
              "token_usage" => 0
            }
          ],
          "previously_completed_jobs" => [
            {
              "step" => "extraction",
              "completed" => "2024-01-01T10:00:00+09:00",
              "duration" => 100.0,
              "params" => { "limit" => 1000 },
              "token_usage" => 5000
            },
            {
              "step" => "embedding",
              "completed" => "2024-01-01T10:10:00+09:00",
              "duration" => 200.0,
              "params" => { "model" => "text-embedding-3-small" },
              "token_usage" => 0
            }
          ]
        }

        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, "status.json"), JSON.generate(python_status))
      end

      let(:status) { Broadlistening::Status.new(output_dir) }

      it "combines completed_jobs and previously_completed_jobs" do
        jobs = status.all_completed_jobs
        expect(jobs.size).to eq(3)
      end

      it "returns current run jobs first" do
        jobs = status.all_completed_jobs
        expect(jobs.first.step).to eq("hierarchical_clustering")
      end

      it "returns previous run jobs after current" do
        jobs = status.all_completed_jobs
        previous_steps = jobs[1..].map(&:step)
        expect(previous_steps).to include("extraction", "embedding")
      end
    end
  end

  describe "Writing Ruby status files (Python-compatible format)" do
    let(:status) { Broadlistening::Status.new(output_dir) }

    let(:plan) do
      [
        Broadlistening::PlanStep.new(step: :extraction, run: true, reason: "no trace of previous run"),
        Broadlistening::PlanStep.new(step: :embedding, run: true, reason: "no trace of previous run")
      ]
    end

    describe "start_pipeline" do
      before { status.start_pipeline(plan) }

      let(:saved_data) { JSON.parse(File.read(File.join(output_dir, "status.json"))) }

      it "writes status as running" do
        expect(saved_data["status"]).to eq("running")
      end

      it "writes plan with step/run/reason structure" do
        expect(saved_data["plan"]).to be_an(Array)
        expect(saved_data["plan"].first).to include("step", "run", "reason")
      end

      it "writes lock_until as ISO8601 string" do
        expect(saved_data["lock_until"]).to match(/^\d{4}-\d{2}-\d{2}T/)
      end

      it "writes start_time as ISO8601 string" do
        expect(saved_data["start_time"]).to match(/^\d{4}-\d{2}-\d{2}T/)
      end

      it "initializes token usage fields" do
        expect(saved_data["total_token_usage"]).to eq(0)
        expect(saved_data["token_usage_input"]).to eq(0)
        expect(saved_data["token_usage_output"]).to eq(0)
      end
    end

    describe "complete_step" do
      before do
        status.start_pipeline(plan)
        status.start_step(:extraction)
        status.complete_step(:extraction, params: { limit: 100, model: "gpt-4o-mini" }, duration: 50.5)
      end

      let(:saved_data) { JSON.parse(File.read(File.join(output_dir, "status.json"))) }

      it "writes completed_jobs array" do
        expect(saved_data["completed_jobs"]).to be_an(Array)
        expect(saved_data["completed_jobs"].size).to eq(1)
      end

      it "writes step name as string" do
        job = saved_data["completed_jobs"].first
        expect(job["step"]).to eq("extraction")
      end

      it "writes duration as number" do
        job = saved_data["completed_jobs"].first
        expect(job["duration"]).to eq(50.5)
      end

      it "writes params as hash" do
        job = saved_data["completed_jobs"].first
        expect(job["params"]).to be_a(Hash)
        expect(job["params"]["limit"]).to eq(100)
      end

      it "clears current_job after completion" do
        expect(saved_data["current_job"]).to be_nil
      end
    end

    describe "complete_pipeline" do
      before do
        status.start_pipeline(plan)
        status.start_step(:extraction)
        status.complete_step(:extraction, params: {}, duration: 10.0)
        status.complete_pipeline
      end

      let(:saved_data) { JSON.parse(File.read(File.join(output_dir, "status.json"))) }

      it "writes status as completed" do
        expect(saved_data["status"]).to eq("completed")
      end

      it "writes end_time" do
        expect(saved_data["end_time"]).to match(/^\d{4}-\d{2}-\d{2}T/)
      end
    end

    describe "error_pipeline" do
      before do
        status.start_pipeline(plan)
        error = StandardError.new("Test error message")
        error.set_backtrace([ "line1", "line2" ])
        status.error_pipeline(error)
      end

      let(:saved_data) { JSON.parse(File.read(File.join(output_dir, "status.json"))) }

      it "writes status as error" do
        expect(saved_data["status"]).to eq("error")
      end

      it "writes error message" do
        expect(saved_data["error"]).to include("StandardError")
        expect(saved_data["error"]).to include("Test error message")
      end

      it "writes error_stack_trace" do
        expect(saved_data["error_stack_trace"]).to include("line1")
      end

      it "writes end_time" do
        expect(saved_data["end_time"]).to match(/^\d{4}-\d{2}-\d{2}T/)
      end
    end
  end

  describe "Step name normalization" do
    # Python uses long step names (hierarchical_clustering)
    # Ruby uses short names (clustering)
    # Status should handle both when reading

    describe "reading Python step names" do
      before do
        python_status = {
          "status" => "completed",
          "completed_jobs" => [
            { "step" => "extraction", "completed" => Time.now.iso8601, "duration" => 1.0, "params" => {}, "token_usage" => 0 },
            { "step" => "hierarchical_clustering", "completed" => Time.now.iso8601, "duration" => 1.0, "params" => {}, "token_usage" => 0 },
            { "step" => "hierarchical_initial_labelling", "completed" => Time.now.iso8601, "duration" => 1.0, "params" => {}, "token_usage" => 0 },
            { "step" => "hierarchical_merge_labelling", "completed" => Time.now.iso8601, "duration" => 1.0, "params" => {}, "token_usage" => 0 },
            { "step" => "hierarchical_overview", "completed" => Time.now.iso8601, "duration" => 1.0, "params" => {}, "token_usage" => 0 },
            { "step" => "hierarchical_aggregation", "completed" => Time.now.iso8601, "duration" => 1.0, "params" => {}, "token_usage" => 0 }
          ],
          "previously_completed_jobs" => []
        }

        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, "status.json"), JSON.generate(python_status))
      end

      let(:status) { Broadlistening::Status.new(output_dir) }

      it "preserves Python step names as-is" do
        # Current behavior: step names are stored as-is
        jobs = status.all_completed_jobs
        step_names = jobs.map(&:step)

        expect(step_names).to include("hierarchical_clustering")
        expect(step_names).to include("hierarchical_initial_labelling")
      end
    end

    describe "writing Ruby step names" do
      let(:status) { Broadlistening::Status.new(output_dir) }

      before do
        plan = [ Broadlistening::PlanStep.new(step: :clustering, run: true, reason: "test") ]
        status.start_pipeline(plan)
        status.start_step(:clustering)
        status.complete_step(:clustering, params: { cluster_nums: [ 5, 15 ] }, duration: 10.0)
      end

      let(:saved_data) { JSON.parse(File.read(File.join(output_dir, "status.json"))) }

      it "writes Ruby step names (short form)" do
        job = saved_data["completed_jobs"].first
        expect(job["step"]).to eq("clustering")
      end
    end
  end

  describe "Cross-platform round-trip" do
    # Simulate: Python writes status -> Ruby reads -> Ruby writes -> verify consistency

    let(:original_python_status) do
      {
        "status" => "completed",
        "start_time" => "2024-01-01T10:00:00+09:00",
        "end_time" => "2024-01-01T10:30:00+09:00",
        "completed_jobs" => [
          {
            "step" => "extraction",
            "completed" => "2024-01-01T10:10:00+09:00",
            "duration" => 600.5,
            "params" => { "limit" => 1000 },
            "token_usage" => 15000
          }
        ],
        "previously_completed_jobs" => [
          {
            "step" => "embedding",
            "completed" => "2024-01-01T09:00:00+09:00",
            "duration" => 300.0,
            "params" => { "model" => "text-embedding-3-small" },
            "token_usage" => 0
          }
        ],
        "total_token_usage" => 15000
      }
    end

    before do
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, "status.json"), JSON.generate(original_python_status))
    end

    it "preserves job data through read/write cycle" do
      # Read Python status
      status = Broadlistening::Status.new(output_dir)
      jobs_before = status.all_completed_jobs

      # Write back
      status.save

      # Read again
      status2 = Broadlistening::Status.new(output_dir)
      jobs_after = status2.all_completed_jobs

      expect(jobs_after.size).to eq(jobs_before.size)
      expect(jobs_after.map(&:step)).to eq(jobs_before.map(&:step))
    end
  end
end
