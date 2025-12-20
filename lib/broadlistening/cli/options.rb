# frozen_string_literal: true

module Broadlistening
  class Cli
    # Options for the broadlistening CLI
    class Options
      attr_accessor :config_path, :force, :only, :skip_interaction,
                    :from_step, :input_dir

      def initialize
        @force = false
        @only = nil
        @skip_interaction = false
        @from_step = nil
        @input_dir = nil
      end

      # Convert to hash for Pipeline options
      def to_pipeline_options
        {
          force: force,
          only: only,
          from_step: from_step,
          input_dir: input_dir
        }.compact
      end

      # Check if resume mode is active
      def resume_mode?
        !!(from_step || input_dir)
      end

      # Validation helper: --from without --input-dir
      def from_step_without_input_dir?
        !!(from_step && !input_dir)
      end

      # Validation helper: --input-dir without --from
      def input_dir_without_from_step?
        !!(input_dir && !from_step)
      end

      # Validation helper: conflicting --from and --only
      def conflicting_options?
        !!(from_step && only)
      end
    end
  end
end
