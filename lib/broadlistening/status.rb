# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "time"

module Broadlistening
  class Status
    LOCK_DURATION = 300 # 5分

    attr_reader :output_dir, :status_file

    def initialize(output_dir)
      @output_dir = Pathname.new(output_dir)
      @status_file = @output_dir / "status.json"
      @data = load_or_initialize
      @completed_jobs = parse_completed_jobs(@data[:completed_jobs])
      @previously_completed_jobs = parse_completed_jobs(@data[:previously_completed_jobs])
    end

    def save
      FileUtils.mkdir_p(output_dir)
      @data[:completed_jobs] = @completed_jobs.map(&:to_h)
      @data[:previously_completed_jobs] = @previously_completed_jobs.map(&:to_h)
      status_file.write(JSON.pretty_generate(@data))
    end

    def start_pipeline(plan)
      @data.merge!(
        status: "running",
        plan: plan.map { |p| serialize_plan_entry(p) },
        start_time: Time.now.iso8601,
        lock_until: lock_time.iso8601,
        total_token_usage: 0,
        token_usage_input: 0,
        token_usage_output: 0
      )
      @completed_jobs = []
      save
    end

    def start_step(step_name)
      @data[:current_job] = step_name.to_s
      @data[:current_job_started] = Time.now.iso8601
      @data[:lock_until] = lock_time.iso8601
      save
    end

    def complete_step(step_name, params:, duration:, token_usage: nil)
      usage = token_usage || TokenUsage.new
      job = CompletedJob.create(
        step: step_name,
        duration: duration,
        params: params,
        token_usage: usage.total
      )
      @completed_jobs << job

      @data[:total_token_usage] = (@data[:total_token_usage] || 0) + usage.total
      @data[:token_usage_input] = (@data[:token_usage_input] || 0) + usage.input
      @data[:token_usage_output] = (@data[:token_usage_output] || 0) + usage.output

      @data.delete(:current_job)
      @data.delete(:current_job_started)
      save
    end

    def complete_pipeline
      merge_previous_jobs
      @data[:status] = "completed"
      @data[:end_time] = Time.now.iso8601
      @data.delete(:previous)
      save
    end

    def error_pipeline(error)
      @data[:status] = "error"
      @data[:end_time] = Time.now.iso8601
      @data[:error] = "#{error.class}: #{error.message}"
      @data[:error_stack_trace] = error.backtrace&.join("\n")
      save
    end

    def locked?
      return false unless @data[:status] == "running"
      return false unless @data[:lock_until]

      Time.parse(@data[:lock_until]) > Time.now
    end

    def all_completed_jobs
      @completed_jobs + @previously_completed_jobs
    end

    private

    def load_or_initialize
      if status_file.exist?
        JSON.parse(status_file.read, symbolize_names: true)
      else
        {
          status: "initialized",
          completed_jobs: [],
          previously_completed_jobs: []
        }
      end
    end

    def parse_completed_jobs(jobs_data)
      (jobs_data || []).map { |j| CompletedJob.from_hash(j) }
    end

    def lock_time
      Time.now + LOCK_DURATION
    end

    def serialize_plan_entry(entry)
      {
        step: entry[:step].to_s,
        run: entry[:run],
        reason: entry[:reason]
      }
    end

    def merge_previous_jobs
      return unless @data[:previous]

      old_jobs = parse_completed_jobs(@data[:previous][:completed_jobs])
      old_jobs += parse_completed_jobs(@data[:previous][:previously_completed_jobs])

      newly_completed_steps = @completed_jobs.map(&:step)
      @previously_completed_jobs = old_jobs.reject { |j| newly_completed_steps.include?(j.step) }
    end
  end
end
