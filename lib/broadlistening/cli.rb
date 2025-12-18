# frozen_string_literal: true

require "optparse"
require "json"
require "pathname"

module Broadlistening
  class CLI
    PIPELINE_DIR = Pathname.new(__dir__).parent.parent / "outputs"

    attr_reader :options

    def initialize(argv = ARGV)
      @argv = argv
      @options = {
        force: false,
        only: nil,
        skip_interaction: false
      }
    end

    def run
      parse_options
      validate_config_path

      config = load_config
      validate_config(config)

      output_dir = determine_output_dir
      ensure_output_dir(output_dir)

      unless @options[:skip_interaction]
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

    def parse_options
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: broadlistening CONFIG [options]"
        opts.separator ""
        opts.separator "Run the broadlistening pipeline with the specified configuration."
        opts.separator ""
        opts.separator "Options:"

        opts.on("-f", "--force", "Force re-run all steps regardless of previous execution") do
          @options[:force] = true
        end

        opts.on("-o", "--only STEP", "Run only the specified step (e.g., extraction, embedding, clustering, etc.)") do |step|
          @options[:only] = step.to_sym
        end

        opts.on("--skip-interaction", "Skip the interactive confirmation prompt and run pipeline immediately") do
          @options[:skip_interaction] = true
        end

        opts.on("-h", "--help", "Show this help message") do
          puts opts
          exit 0
        end

        opts.on("-v", "--version", "Show version") do
          puts "broadlistening #{Broadlistening::VERSION}"
          exit 0
        end
      end

      parser.parse!(@argv)
      @config_path = @argv.first
    end

    def validate_config_path
      unless @config_path
        $stderr.puts "Error: CONFIG is required"
        $stderr.puts "Usage: broadlistening CONFIG [options]"
        exit 1
      end

      unless File.exist?(@config_path)
        $stderr.puts "Error: Config file not found: #{@config_path}"
        exit 1
      end
    end

    def load_config
      Config.from_file(@config_path)
    rescue JSON::ParserError => e
      raise Broadlistening::ConfigurationError, "Invalid JSON in config file: #{e.message}"
    end

    def validate_config(config)
      raise Broadlistening::ConfigurationError, "Missing required field 'input' in config" unless config.input
      raise Broadlistening::ConfigurationError, "Missing required field 'question' in config" unless config.question
      raise Broadlistening::ConfigurationError, "Input file not found: #{config.input}" unless File.exist?(config.input)
    end

    def determine_output_dir
      # Python版と同様: 設定ファイル名から出力ディレクトリを決定
      # e.g., "config/my_report.json" -> "outputs/my_report"
      config_basename = File.basename(@config_path, ".*")
      PIPELINE_DIR / config_basename
    end

    def ensure_output_dir(output_dir)
      FileUtils.mkdir_p(output_dir) unless output_dir.exist?
    end

    def show_plan(config, output_dir)
      puts "So, here is what I am planning to run:"

      planner = create_planner(config, output_dir)
      plan = planner.create_plan(force: @options[:force], only: @options[:only])

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
        force: @options[:force],
        only: @options[:only]
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
