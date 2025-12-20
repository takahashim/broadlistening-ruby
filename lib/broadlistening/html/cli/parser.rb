# frozen_string_literal: true

require "optparse"

module Broadlistening
  module Html
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
          options.input_path = argv[0]
          options.output_path = argv[1] if argv[1]

          options
        end

        private

        def option_parser(options)
          OptionParser.new do |opts|
            opts.banner = "Usage: broadlistening-html INPUT_JSON [OUTPUT_HTML] [options]"
            opts.separator ""
            opts.separator "Generate HTML report from hierarchical_result.json for preview."
            opts.separator ""
            opts.separator "Arguments:"
            opts.separator "  INPUT_JSON   Path to hierarchical_result.json"
            opts.separator "  OUTPUT_HTML  Output HTML path (default: report.html)"
            opts.separator ""
            opts.separator "Options:"

            opts.on("-t", "--template PATH", "Custom ERB template for HTML output") do |path|
              options.template = path
            end

            opts.on("--title TITLE", "HTML page title") do |title|
              options.title = title
            end

            opts.on("-h", "--help", "Show this help message") do
              puts opts
              exit 0
            end

            opts.on("-v", "--version", "Show version") do
              puts "broadlistening-html #{Broadlistening::VERSION}"
              exit 0
            end
          end
        end
      end
    end
  end
end
