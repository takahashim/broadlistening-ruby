# frozen_string_literal: true

module Broadlistening
  class Cli
    # Validates CLI options and configuration
    class Validator
      class << self
        def validate!(options)
          validate_config_path!(options)
          validate_resume_options!(options)
          validate_input_files!(options) if options.from_step && options.input_dir
        end

        def validate_config!(config, options = nil)
          input_file = options&.input_file || config.input
          raise ConfigurationError, "Missing input file: specify with --input or in config" unless input_file
          raise ConfigurationError, "Missing required field 'question' in config" unless config.question
          raise ConfigurationError, "Input file not found: #{input_file}" unless File.exist?(input_file)
        end

        private

        def validate_config_path!(options)
          unless options.config_path
            $stderr.puts "Error: CONFIG is required"
            $stderr.puts "Usage: broadlistening CONFIG [options]"
            exit 1
          end

          return if File.exist?(options.config_path)

          $stderr.puts "Error: Config file not found: #{options.config_path}"
          exit 1
        end

        def validate_resume_options!(options)
          if options.input_dir_without_from_step?
            $stderr.puts "Error: --from is required when using --input-dir"
            exit 1
          end

          return unless options.conflicting_options?

          $stderr.puts "Error: --from and --only cannot be used together"
          exit 1
        end

        def validate_input_files!(options)
          spec_loader = SpecLoader.default
          steps = spec_loader.steps
          from_index = steps.index(options.from_step)

          unless from_index
            $stderr.puts "Error: Unknown step '#{options.from_step}'"
            $stderr.puts "Valid steps: #{steps.join(', ')}"
            exit 1
          end

          required_files = steps[0...from_index].flat_map do |step|
            file_config = Context::OUTPUT_FILES[step]
            case file_config
            when Hash then file_config.values
            when String then [ file_config ]
            else []
            end
          end

          missing = required_files.reject { |f| File.exist?(File.join(options.input_dir, f)) }

          return unless missing.any?

          $stderr.puts "Error: Required files not found in '#{options.input_dir}':"
          missing.each { |f| $stderr.puts "  - #{f}" }
          exit 1
        end
      end
    end
  end
end
