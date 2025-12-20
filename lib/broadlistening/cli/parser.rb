# frozen_string_literal: true

require "optparse"

module Broadlistening
  class Cli
    # Parses CLI arguments and returns Options
    class Parser
      def self.parse(argv)
        new.parse(argv)
      end

      def parse(argv)
        argv = argv.dup
        options = Options.new

        option_parser(options).parse!(argv)
        options.config_path = argv.first

        options
      end

      private

      def option_parser(options)
        OptionParser.new do |opts|
          opts.banner = "Usage: broadlistening CONFIG [options]"
          opts.separator ""
          opts.separator "Run the broadlistening pipeline with the specified configuration."
          opts.separator ""
          opts.separator "Options:"

          opts.on("-f", "--force", "Force re-run all steps regardless of previous execution") do
            options.force = true
          end

          opts.on("-o", "--only STEP", "Run only the specified step (e.g., extraction, embedding, clustering, etc.)") do |step|
            options.only = step.to_sym
          end

          opts.on("-n", "--dry-run", "Show what would be executed without actually running the pipeline") do
            options.dry_run = true
          end

          opts.on("-V", "--verbose", "Show detailed output including step parameters and LLM usage") do
            options.verbose = true
          end

          opts.on("--from STEP", "Resume pipeline from specified step") do |step|
            options.from_step = step.to_sym
          end

          opts.on("--input-dir DIR", "Use different input directory for resuming (requires --from)") do |dir|
            options.input_dir = dir
          end

          opts.on("-i", "--input FILE", "Input file path (CSV or JSON) - overrides config") do |file|
            options.input_file = file
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
      end
    end
  end
end
