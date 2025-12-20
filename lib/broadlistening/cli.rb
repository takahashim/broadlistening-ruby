# frozen_string_literal: true

require "json"
require "pathname"

module Broadlistening
  class Cli
    PIPELINE_DIR = Pathname.new(__dir__).parent.parent / "outputs"

    attr_reader :options

    def initialize(argv = ARGV)
      @argv = argv
    end

    def run
      @options = Parser.parse(@argv)
      Validator.validate!(@options)

      config = load_config
      Validator.validate_config!(config)

      output_dir = determine_output_dir
      ensure_output_dir(output_dir)

      unless @options.skip_interaction
        show_plan(config, output_dir)
        confirm_execution || exit(0)
      end

      execute_pipeline(config, output_dir)
    rescue Broadlistening::Error => e
      $stderr.puts "Error: #{e.message}"
      exit 1
    rescue Interrupt
      $stderr.puts "\nInterrupted"
      exit 130
    end

    private

    def load_config
      Config.from_file(@options.config_path)
    rescue JSON::ParserError => e
      raise Broadlistening::ConfigurationError, "Invalid JSON in config file: #{e.message}"
    end

    def determine_output_dir
      # Python版と同様: 設定ファイル名から出力ディレクトリを決定
      # e.g., "config/my_report.json" -> "outputs/my_report"
      config_basename = File.basename(@options.config_path, ".*")
      PIPELINE_DIR / config_basename
    end

    def ensure_output_dir(output_dir)
      FileUtils.mkdir_p(output_dir) unless output_dir.exist?
    end

    def show_plan(config, output_dir)
      puts "So, here is what I am planning to run:"

      planner = create_planner(config, output_dir)
      plan = planner.create_plan(
        force: @options.force,
        only: @options.only,
        from_step: @options.from_step
      )

      plan.each do |step|
        status = step.run? ? "RUN" : "SKIP"
        puts "  #{step.step}: #{status} (#{step.reason})"
      end

      puts ""
    end

    def confirm_execution
      print "Looks good? Press enter to continue or Ctrl+C to abort."
      $stdin.gets
      true
    rescue Interrupt
      puts ""
      false
    end

    def create_planner(config, output_dir)
      status = Status.new(output_dir)
      Planner.new(config: config, status: status, output_dir: output_dir)
    end

    def execute_pipeline(config, output_dir)
      comments = load_comments(config.input)

      pipeline = Pipeline.new(config)

      setup_progress_output

      result = pipeline.run(
        comments,
        output_dir: output_dir.to_s,
        force: @options.force,
        only: @options.only,
        from_step: @options.from_step,
        input_dir: @options.input_dir
      )

      puts ""
      puts "Pipeline completed."

      result
    end

    def load_comments(input_path)
      case File.extname(input_path).downcase
      when ".csv"
        CsvLoader.load(input_path)
      when ".json"
        JSON.parse(File.read(input_path), symbolize_names: true)
      else
        raise Broadlistening::ConfigurationError, "Unsupported input format: #{File.extname(input_path)}"
      end
    end

    def setup_progress_output
      ActiveSupport::Notifications.subscribe("step.broadlistening") do |*, payload|
        puts "Running step: #{payload[:step]}"
      end

      ActiveSupport::Notifications.subscribe("step.skip.broadlistening") do |*, payload|
        puts "Skipping '#{payload[:step]}'"
      end

      ActiveSupport::Notifications.subscribe("progress.broadlistening") do |*, payload|
        step = payload[:step]
        current = payload[:current]
        total = payload[:total]
        print "\r  #{step}: #{current}/#{total}"
        puts "" if current == total
      end
    end
  end
end
