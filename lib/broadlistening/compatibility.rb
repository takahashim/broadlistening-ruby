# frozen_string_literal: true

require "json"
require "json_schemer"

module Broadlistening
  # Compatibility utilities for comparing outputs between
  # Kouchou-AI (Python) and Broadlistening gem (Ruby) implementations.
  #
  # @example Compare two output files
  #   report = Compatibility.compare_outputs(
  #     python_output: "path/to/python/result.json",
  #     ruby_output: "path/to/ruby/result.json"
  #   )
  #   puts report.summary
  #
  # @example Validate output against schema
  #   errors = Compatibility.validate_output(result_hash)
  module Compatibility
    # Expected structure for hierarchical_result.json
    REQUIRED_TOP_LEVEL_KEYS = %w[arguments clusters comments propertyMap translations overview config].freeze
    REQUIRED_ARGUMENT_KEYS = %w[arg_id argument comment_id x y cluster_ids].freeze
    REQUIRED_CLUSTER_KEYS = %w[level id label takeaway value parent].freeze

    # Path to JSON Schema file
    SCHEMA_PATH = File.expand_path("../../schema/hierarchical_result.json", __dir__)

    class ComparisonReport
      attr_accessor :differences, :python_stats, :ruby_stats

      def initialize
        @differences = []
        @python_stats = {}
        @ruby_stats = {}
      end

      def add_difference(category, message, details = {})
        @differences << {
          category: category,
          message: message,
          details: details
        }
      end

      def compatible?
        @differences.empty?
      end

      def summary
        lines = []
        lines << "=" * 60
        lines << "Compatibility Report"
        lines << "=" * 60
        lines << ""

        lines << "Python Output Stats:"
        @python_stats.each { |k, v| lines << "  #{k}: #{v}" }
        lines << ""

        lines << "Ruby Output Stats:"
        @ruby_stats.each { |k, v| lines << "  #{k}: #{v}" }
        lines << ""

        if compatible?
          lines << "Result: COMPATIBLE"
        else
          lines << "Result: INCOMPATIBLE (#{@differences.size} differences found)"
          lines << ""
          lines << "Differences:"
          @differences.each_with_index do |diff, i|
            lines << "  #{i + 1}. [#{diff[:category]}] #{diff[:message]}"
            diff[:details].each { |k, v| lines << "      #{k}: #{v}" } if diff[:details].any?
          end
        end

        lines << ""
        lines << "=" * 60
        lines.join("\n")
      end

      def to_h
        {
          compatible: compatible?,
          python_stats: @python_stats,
          ruby_stats: @ruby_stats,
          differences: @differences
        }
      end
    end

    class << self
      # Compare outputs from Python and Ruby implementations
      #
      # @param python_output [String, Hash] Path to JSON file or parsed hash
      # @param ruby_output [String, Hash] Path to JSON file or parsed hash
      # @return [ComparisonReport]
      def compare_outputs(python_output:, ruby_output:)
        python_data = load_output(python_output)
        ruby_data = load_output(ruby_output)

        report = ComparisonReport.new
        report.python_stats = collect_stats(python_data)
        report.ruby_stats = collect_stats(ruby_data)

        compare_structure(python_data, ruby_data, report)
        compare_arguments(python_data, ruby_data, report)
        compare_clusters(python_data, ruby_data, report)
        compare_overview(python_data, ruby_data, report)

        report
      end

      # Validate output structure
      #
      # @param output [Hash] Parsed output hash
      # @return [Array<String>] List of validation errors
      def validate_output(output)
        errors = []

        # Check top-level keys
        missing_keys = REQUIRED_TOP_LEVEL_KEYS - output.keys.map(&:to_s)
        errors << "Missing top-level keys: #{missing_keys.join(', ')}" if missing_keys.any?

        # Check arguments structure
        if output["arguments"] || output[:arguments]
          args = output["arguments"] || output[:arguments]
          if args.is_a?(Array) && args.any?
            sample = args.first
            sample_keys = sample.keys.map(&:to_s)
            missing_arg_keys = REQUIRED_ARGUMENT_KEYS - sample_keys
            errors << "Missing argument keys: #{missing_arg_keys.join(', ')}" if missing_arg_keys.any?
          end
        end

        # Check clusters structure
        if output["clusters"] || output[:clusters]
          clusters = output["clusters"] || output[:clusters]
          if clusters.is_a?(Array) && clusters.any?
            sample = clusters.first
            sample_keys = sample.keys.map(&:to_s)
            missing_cluster_keys = REQUIRED_CLUSTER_KEYS - sample_keys
            errors << "Missing cluster keys: #{missing_cluster_keys.join(', ')}" if missing_cluster_keys.any?
          end
        end

        errors
      end

      # Check if output is structurally compatible with Kouchou-AI format
      #
      # @param output [Hash] Parsed output hash
      # @return [Boolean]
      def valid_output?(output)
        validate_output(output).empty?
      end

      # Validate output against JSON Schema
      #
      # @param output [Hash, String] Parsed output hash or path to JSON file
      # @return [Array<Hash>] List of validation errors from JSON Schema
      def validate_with_schema(output)
        data = output.is_a?(String) ? JSON.parse(File.read(output)) : output
        data = deep_stringify_keys(data) if data.is_a?(Hash)

        schema = JSONSchemer.schema(Pathname.new(SCHEMA_PATH))
        errors = schema.validate(data).to_a

        errors.map do |error|
          {
            path: error["data_pointer"],
            message: error["error"],
            details: error["details"] || {}
          }
        end
      end

      # Check if output is valid according to JSON Schema
      #
      # @param output [Hash, String] Parsed output hash or path to JSON file
      # @return [Boolean]
      def valid_schema?(output)
        validate_with_schema(output).empty?
      end

      # Get the JSON Schema as a Hash
      #
      # @return [Hash] The JSON Schema
      def schema
        @schema ||= JSON.parse(File.read(SCHEMA_PATH))
      end

      # Get the path to the JSON Schema file
      #
      # @return [String] Path to schema file
      def schema_path
        SCHEMA_PATH
      end

      private

      def load_output(output)
        case output
        when String
          JSON.parse(File.read(output))
        when Hash
          deep_stringify_keys(output)
        else
          raise ArgumentError, "Output must be a file path (String) or Hash"
        end
      end

      def deep_stringify_keys(hash)
        hash.transform_keys(&:to_s).transform_values do |v|
          case v
          when Hash then deep_stringify_keys(v)
          when Array then v.map { |e| e.is_a?(Hash) ? deep_stringify_keys(e) : e }
          else v
          end
        end
      end

      def collect_stats(data)
        {
          argument_count: data["arguments"]&.size || 0,
          cluster_count: data["clusters"]&.size || 0,
          cluster_levels: data["clusters"]&.map { |c| c["level"] }&.uniq&.sort || [],
          has_overview: !data["overview"].to_s.strip.empty?,
          has_property_map: data["propertyMap"]&.any? || false,
          top_level_keys: data.keys.sort
        }
      end

      def compare_structure(python, ruby, report)
        python_keys = python.keys.sort
        ruby_keys = ruby.keys.sort

        missing_in_ruby = python_keys - ruby_keys
        extra_in_ruby = ruby_keys - python_keys

        if missing_in_ruby.any?
          report.add_difference(
            :structure,
            "Missing top-level keys in Ruby output",
            missing: missing_in_ruby
          )
        end

        if extra_in_ruby.any?
          report.add_difference(
            :structure,
            "Extra top-level keys in Ruby output",
            extra: extra_in_ruby
          )
        end
      end

      def compare_arguments(python, ruby, report)
        python_args = python["arguments"] || []
        ruby_args = ruby["arguments"] || []

        # Compare argument structure (keys)
        if python_args.any? && ruby_args.any?
          python_keys = python_args.first.keys.sort
          ruby_keys = ruby_args.first.keys.sort

          missing_keys = python_keys - ruby_keys
          if missing_keys.any?
            report.add_difference(
              :arguments,
              "Missing argument keys in Ruby output",
              missing: missing_keys
            )
          end
        end

        # Compare cluster_ids format
        if python_args.any? && ruby_args.any?
          python_cluster_ids = python_args.first["cluster_ids"]
          ruby_cluster_ids = ruby_args.first["cluster_ids"]

          if python_cluster_ids.is_a?(Array) && ruby_cluster_ids.is_a?(Array)
            # Check format consistency (e.g., "0", "1_5", "2_10")
            python_format = detect_cluster_id_format(python_cluster_ids)
            ruby_format = detect_cluster_id_format(ruby_cluster_ids)

            if python_format != ruby_format
              report.add_difference(
                :arguments,
                "cluster_ids format mismatch",
                python_format: python_format,
                ruby_format: ruby_format
              )
            end
          end
        end
      end

      def compare_clusters(python, ruby, report)
        python_clusters = python["clusters"] || []
        ruby_clusters = ruby["clusters"] || []

        # Compare cluster structure
        if python_clusters.any? && ruby_clusters.any?
          python_keys = python_clusters.first.keys.sort
          ruby_keys = ruby_clusters.first.keys.sort

          missing_keys = python_keys - ruby_keys
          if missing_keys.any?
            report.add_difference(
              :clusters,
              "Missing cluster keys in Ruby output",
              missing: missing_keys
            )
          end
        end

        # Compare hierarchy levels
        python_levels = python_clusters.map { |c| c["level"] }.uniq.sort
        ruby_levels = ruby_clusters.map { |c| c["level"] }.uniq.sort

        if python_levels != ruby_levels
          report.add_difference(
            :clusters,
            "Cluster hierarchy levels differ",
            python_levels: python_levels,
            ruby_levels: ruby_levels
          )
        end

        # Compare root cluster
        python_root = python_clusters.find { |c| c["level"] == 0 }
        ruby_root = ruby_clusters.find { |c| c["level"] == 0 }

        if python_root && ruby_root
          if python_root["id"] != ruby_root["id"]
            report.add_difference(
              :clusters,
              "Root cluster ID differs",
              python_id: python_root["id"],
              ruby_id: ruby_root["id"]
            )
          end
        end
      end

      def compare_overview(python, ruby, report)
        python_overview = python["overview"].to_s.strip
        ruby_overview = ruby["overview"].to_s.strip

        if python_overview.empty? != ruby_overview.empty?
          report.add_difference(
            :overview,
            "Overview presence differs",
            python_has_overview: !python_overview.empty?,
            ruby_has_overview: !ruby_overview.empty?
          )
        end
      end

      def detect_cluster_id_format(cluster_ids)
        return :empty if cluster_ids.empty?

        formats = cluster_ids.map do |id|
          case id.to_s
          when /^\d+$/ then :numeric
          when /^\d+_\d+$/ then :level_index
          else :other
          end
        end

        formats.uniq.size == 1 ? formats.first : :mixed
      end
    end
  end
end
