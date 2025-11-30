# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "time"
require "digest"

module Broadlistening
  class Status
    LOCK_DURATION = 300 # 5分

    attr_reader :output_dir, :status_file, :data

    def initialize(output_dir)
      @output_dir = Pathname.new(output_dir)
      @status_file = @output_dir / "status.json"
      @data = load_or_initialize
    end

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

    def save
      FileUtils.mkdir_p(output_dir)
      status_file.write(JSON.pretty_generate(@data))
    end

    def start_pipeline(plan)
      @data.merge!(
        status: "running",
        plan: plan.map { |p| serialize_plan_entry(p) },
        start_time: Time.now.iso8601,
        completed_jobs: [],
        lock_until: lock_time.iso8601
      )
      save
    end

    def start_step(step_name)
      @data[:current_job] = step_name.to_s
      @data[:current_job_started] = Time.now.iso8601
      @data[:lock_until] = lock_time.iso8601
      save
    end

    def complete_step(step_name, params:, duration:, token_usage: 0)
      @data[:completed_jobs] ||= []
      @data[:completed_jobs] << {
        step: step_name.to_s,
        completed: Time.now.iso8601,
        duration: duration,
        params: serialize_params(params),
        token_usage: token_usage
      }
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

    def previous_completed_jobs
      (@data[:completed_jobs] || []) + (@data[:previously_completed_jobs] || [])
    end

    private

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

    def serialize_params(params)
      params.transform_values do |v|
        # プロンプトなど長い文字列はハッシュ化して保存（サイズ削減・比較用）
        if v.is_a?(String) && v.length > 100
          Digest::SHA256.hexdigest(v)
        else
          v
        end
      end
    end

    def merge_previous_jobs
      return unless @data[:previous]

      old_jobs = @data[:previous][:completed_jobs] || []
      old_jobs += @data[:previous][:previously_completed_jobs] || []

      newly_completed = @data[:completed_jobs].map { |j| j[:step] }
      @data[:previously_completed_jobs] = old_jobs.reject { |j| newly_completed.include?(j[:step]) }
    end
  end
end
