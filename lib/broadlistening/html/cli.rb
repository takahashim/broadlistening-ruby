# frozen_string_literal: true

require_relative "cli/options"
require_relative "cli/parser"

module Broadlistening
  module Html
    # CLI for generating HTML reports from hierarchical_result.json
    class Cli
      attr_reader :options

      def initialize(argv = ARGV)
        @argv = argv
      end

      def run
        @options = Parser.parse(@argv)
        @options.validate!
        renderer = Renderer.from_json(@options.input_path, @options.to_h)
        renderer.save(@options.output_path)
        puts "HTML report generated: #{@options.output_path}"
      rescue JSON::ParserError => e
        abort "Error: Invalid JSON in input file: #{e.message}"
      rescue Broadlistening::Error => e
        abort "Error: #{e.message}"
      rescue Interrupt
        abort "\nInterrupted"
      end
    end
  end
end
