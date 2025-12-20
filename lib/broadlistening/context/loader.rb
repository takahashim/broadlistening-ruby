# frozen_string_literal: true

require "csv"
require "json"
require "pathname"

module Broadlistening
  class Context
    # Loads Context data from output files.
    #
    # @example
    #   context = Context.new
    #   Context::Loader.load_from_dir(context, "/path/to/output")
    class Loader
      # Load existing context from output directory
      #
      # @param context [Context] The context to populate
      # @param output_dir [String, Pathname] Directory containing output files
      # @return [Context] The populated context
      def self.load_from_dir(context, output_dir)
        new(context, Pathname.new(output_dir)).load
      end

      def initialize(context, dir)
        @context = context
        @dir = dir
      end

      def load
        Context::OUTPUT_FILES.each do |step, file_config|
          load_step(step, file_config)
        end
        @context
      end

      private

      def load_step(step, file_config)
        case step
        when :extraction then load_extraction(file_config)
        when :embedding then load_embedding(file_config)
        when :clustering then load_clustering(file_config)
        when :initial_labelling then load_initial_labels(file_config)
        when :merge_labelling then load_merge_labels(file_config)
        when :overview then load_overview(file_config)
        end
      end

      def load_extraction(file_config)
        args_file = @dir / file_config[:args]
        relations_file = @dir / file_config[:relations]
        return unless args_file.exist?

        # Load relations first to build the mapping
        relations_map = load_relations_map(relations_file)

        CSV.foreach(args_file, headers: true) do |row|
          arg_id = row["arg-id"]
          comment_id = relations_map[arg_id]
          raise Error, "Missing comment_id for argument #{arg_id}. Ensure relations.csv exists." unless comment_id

          @context.arguments << Argument.new(
            arg_id: arg_id,
            argument: row["argument"],
            comment_id: comment_id
          )
        end
      end

      def load_relations_map(relations_file)
        raise Error, "relations.csv not found: #{relations_file}" unless relations_file.exist?

        relations_map = {}
        CSV.foreach(relations_file, headers: true) do |row|
          relations_map[row["arg-id"]] = row["comment-id"]
          @context.relations << Relation.new(arg_id: row["arg-id"], comment_id: row["comment-id"])
        end
        relations_map
      end

      def load_embedding(filename)
        file = @dir / filename
        return unless file.exist?

        data = JSON.parse(file.read, symbolize_names: true)
        return unless data[:arguments]

        embedding_map = data[:arguments].to_h { |e| [ e[:arg_id], e[:embedding] ] }
        @context.arguments.each do |arg|
          embedding = embedding_map[arg.arg_id]
          arg.embedding = embedding if embedding
        end
      end

      def load_clustering(filename)
        file = @dir / filename
        return unless file.exist?

        headers = CSV.read(file, headers: true).headers
        cluster_columns = headers.select { |h| h&.match?(/^cluster-level-\d+-id$/) }
        max_level = cluster_columns.map { |c| c[/\d+/].to_i }.max || 0

        CSV.foreach(file, headers: true) do |row|
          arg = @context.arguments.find { |a| a.arg_id == row["arg-id"] }
          next unless arg

          arg.x = row["x"].to_f
          arg.y = row["y"].to_f

          cluster_ids = [ "0" ]
          (1..max_level).each do |level|
            cluster_id = row["cluster-level-#{level}-id"]
            cluster_ids << cluster_id if cluster_id
          end
          arg.cluster_ids = cluster_ids
        end

        rebuild_cluster_results
      end

      def load_initial_labels(filename)
        file = @dir / filename
        return unless file.exist?

        headers = CSV.read(file, headers: true).headers
        label_columns = headers.select { |h| h&.match?(/^cluster-level-\d+-label$/) }
        max_level = label_columns.map { |c| c[/\d+/].to_i }.max || 0

        CSV.foreach(file, headers: true) do |row|
          arg = @context.arguments.find { |a| a.arg_id == row["arg-id"] }
          if arg
            arg.x = row["x"].to_f if row["x"]
            arg.y = row["y"].to_f if row["y"]
          end

          cluster_id = row["cluster-level-#{max_level}-id"]
          next unless cluster_id && !@context.initial_labels.key?(cluster_id)

          label = row["cluster-level-#{max_level}-label"]
          description = row["cluster-level-#{max_level}-description"]
          next unless label

          @context.initial_labels[cluster_id] = ClusterLabel.new(
            cluster_id: cluster_id,
            level: max_level,
            label: label,
            description: description || ""
          )
        end
      end

      def load_merge_labels(filename)
        file = @dir / filename
        return unless file.exist?

        CSV.foreach(file, headers: true) do |row|
          cluster_id = row["id"]
          @context.labels[cluster_id] = ClusterLabel.new(
            cluster_id: cluster_id,
            level: row["level"].to_i,
            label: row["label"],
            description: row["description"] || ""
          )
        end
      end

      def load_overview(filename)
        file = @dir / filename
        return unless file.exist?

        @context.overview = file.read.strip
      end

      def rebuild_cluster_results
        @context.cluster_results = ClusterResults.new
        @context.arguments.each_with_index do |arg, idx|
          next unless arg.cluster_ids

          arg.cluster_ids.each_with_index do |cluster_id, level|
            next if level == 0

            cluster_num = cluster_id.split("_").last.to_i
            @context.cluster_results.set(level, idx, cluster_num)
          end
        end
      end
    end
  end
end
