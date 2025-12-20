# frozen_string_literal: true

module Broadlistening
  module Html
    class Cli
      # Options for HTML generation
      class Options
        attr_accessor :input_path, :output_path, :template, :title

        def initialize
          @output_path = "report.html"
        end

        def validate!
          raise ConfigurationError, "INPUT_JSON is required" unless input_path
          raise ConfigurationError, "Input file not found: #{input_path}" unless File.exist?(input_path)
          raise ConfigurationError, "Template file not found: #{template}" if template && !File.exist?(template)
        end

        def to_h
          { template: template, title: title }.compact
        end
      end
    end
  end
end
