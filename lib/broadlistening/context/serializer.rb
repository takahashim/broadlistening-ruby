# frozen_string_literal: true

require "csv"
require "json"
require "pathname"
require "fileutils"

module Broadlistening
  class Context
    # Serializes Context data to output files.
    #
    # @example
    #   context = Context.new
    #   # ... populate context ...
    #   Context::Serializer.save_step(context, :extraction, "/path/to/output")
    class Serializer
      # Save a step's output to file
      #
      # @param context [Context] The context to save
      # @param step_name [Symbol] The step name
      # @param output_dir [String, Pathname] Output directory
      def self.save_step(context, step_name, output_dir)
        new(context, Pathname.new(output_dir)).save_step(step_name)
      end

      def initialize(context, dir)
        @context = context
        @dir = dir
      end

      def save_step(step_name)
        file_config = Context::OUTPUT_FILES[step_name]
        return unless file_config

        FileUtils.mkdir_p(@dir)

        case step_name
        when :extraction then save_extraction(file_config)
        when :embedding then save_embedding(file_config)
        when :clustering then save_clustering(file_config)
        when :initial_labelling then save_initial_labels(file_config)
        when :merge_labelling then save_merge_labels(file_config)
        when :overview then save_overview(file_config)
        when :aggregation then save_aggregation(file_config)
        end
      end

      private

      def save_extraction(file_config)
        CSV.open(@dir / file_config[:args], "w") do |csv|
          csv << [ "arg-id", "argument" ]
          @context.arguments.each do |arg|
            csv << [ arg.arg_id, arg.argument ]
          end
        end

        CSV.open(@dir / file_config[:relations], "w") do |csv|
          csv << [ "arg-id", "comment-id" ]
          @context.relations.each do |rel|
            csv << [ rel.arg_id, rel.comment_id ]
          end
        end
      end

      def save_embedding(filename)
        data = { arguments: @context.arguments.map(&:to_embedding_h) }
        File.write(@dir / filename, JSON.pretty_generate(data))
      end

      def save_clustering(filename)
        return if @context.arguments.empty?

        max_level = calculate_max_level
        CSV.open(@dir / filename, "w") do |csv|
          csv << clustering_headers(max_level)
          @context.arguments.each { |arg| csv << clustering_row(arg, max_level) }
        end
      end

      def save_initial_labels(filename)
        return if @context.arguments.empty?

        max_level = calculate_max_level
        CSV.open(@dir / filename, "w") do |csv|
          csv << initial_labels_headers(max_level)
          @context.arguments.each { |arg| csv << initial_labels_row(arg, max_level) }
        end
      end

      def save_merge_labels(filename)
        clusters = DensityCalculator::ClusterPoints.build_from(@context.arguments, @context.labels)
        densities = DensityCalculator.calculate_with_ranks(clusters)

        CSV.open(@dir / filename, "w") do |csv|
          csv << [ "level", "id", "label", "description", "value", "parent",
                  "density", "density_rank", "density_rank_percentile" ]

          @context.labels.each_value do |label|
            csv << merge_labels_row(label, densities)
          end
        end
      end

      def save_overview(filename)
        File.write(@dir / filename, @context.overview || "")
      end

      def save_aggregation(filename)
        return unless @context.result

        File.write(@dir / filename, JSON.pretty_generate(@context.result.to_h))
      end

      # Helper methods

      def calculate_max_level
        max = @context.arguments.map { |a| a.cluster_ids&.length || 0 }.max - 1
        [ max, 0 ].max
      end

      def clustering_headers(max_level)
        headers = [ "arg-id", "argument", "x", "y" ]
        (1..max_level).each { |level| headers << "cluster-level-#{level}-id" }
        headers
      end

      def clustering_row(arg, max_level)
        row = [ arg.arg_id, arg.argument, arg.x, arg.y ]
        (1..max_level).each do |level|
          row << (arg.cluster_ids&.dig(level) || "")
        end
        row
      end

      def initial_labels_headers(max_level)
        headers = [ "arg-id", "argument", "x", "y" ]
        (1..max_level).each do |level|
          headers << "cluster-level-#{level}-id"
          headers << "cluster-level-#{level}-label"
          headers << "cluster-level-#{level}-description"
        end
        headers
      end

      def initial_labels_row(arg, max_level)
        row = [ arg.arg_id, arg.argument, arg.x, arg.y ]
        (1..max_level).each do |level|
          cluster_id = arg.cluster_ids&.dig(level)
          label_obj = @context.initial_labels[cluster_id] || @context.labels[cluster_id]
          row << (cluster_id || "")
          row << (label_obj&.label || "")
          row << (label_obj&.description || "")
        end
        row
      end

      def merge_labels_row(label, densities)
        value = @context.arguments.count { |a| a.cluster_ids&.include?(label.cluster_id) }
        parent = find_parent_cluster(label.cluster_id)
        density_info = densities[label.cluster_id]

        [
          label.level,
          label.cluster_id,
          label.label,
          label.description,
          value,
          parent,
          density_info&.density || "",
          density_info&.density_rank || "",
          density_info&.density_rank_percentile || ""
        ]
      end

      def find_parent_cluster(cluster_id)
        return "0" unless cluster_id

        arg = @context.arguments.find { |a| a.cluster_ids&.include?(cluster_id) }
        return "0" unless arg&.cluster_ids

        idx = arg.cluster_ids.index(cluster_id)
        return "0" unless idx && idx > 0

        arg.cluster_ids[idx - 1]
      end
    end
  end
end
