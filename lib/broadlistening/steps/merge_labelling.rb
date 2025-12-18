# frozen_string_literal: true

module Broadlistening
  module Steps
    class MergeLabelling < BaseStep
      def execute
        return context if context.initial_labels.empty?

        all_labels = context.initial_labels.dup

        # Build parent-child relationships and merge from bottom to top
        levels = context.cluster_results.levels.reverse
        levels[1..].each do |level|
          parent_labels = merge_labels_for_level(context.arguments, all_labels, context.cluster_results, level)
          parent_labels.each { |l| all_labels[l.cluster_id] = l }
        end

        context.labels = all_labels
        context
      end

      private

      def merge_labels_for_level(arguments, all_labels, cluster_results, level)
        child_level = level + 1
        parent_clusters = cluster_results.unique_clusters(level)
        total = parent_clusters.size
        mutex = Mutex.new
        processed = 0

        Parallel.map(parent_clusters, in_threads: config.workers) do |parent_cluster_id|
          result = merge_single_parent(arguments, all_labels, cluster_results, level, child_level, parent_cluster_id)
          current = mutex.synchronize { processed += 1 }
          notify_progress(current: current, total: total, message: "level #{level}")
          result
        end
      end

      def merge_single_parent(arguments, all_labels, cluster_results, level, child_level, parent_cluster_id)
        child_cluster_ids = find_child_clusters(arguments, cluster_results, level, child_level, parent_cluster_id)
        child_labels = child_cluster_ids.filter_map { |cid| all_labels["#{child_level}_#{cid}"] }

        return default_label(level, parent_cluster_id) if child_labels.empty?

        input = child_labels.map { |l| "- #{l.label}: #{l.description}" }.join("\n")

        result = llm_client.chat(
          system: config.prompts[:merge_labelling],
          user: input,
          json_mode: true
        )
        context.add_token_usage(result.token_usage)

        parse_label_response(result.content, level, parent_cluster_id)
      rescue StandardError => e
        warn "Failed to merge labels for cluster #{level}_#{parent_cluster_id}: #{e.message}"
        default_label(level, parent_cluster_id)
      end

      def find_child_clusters(arguments, cluster_results, parent_level, child_level, parent_cluster_id)
        child_clusters = Set.new

        arguments.each_with_index do |_arg, idx|
          next unless cluster_results.cluster_at(parent_level, idx) == parent_cluster_id

          child_clusters.add(cluster_results.cluster_at(child_level, idx))
        end

        child_clusters.to_a
      end

      def parse_label_response(content, level, cluster_id)
        parsed = JSON.parse(content)
        ClusterLabel.new(
          cluster_id: "#{level}_#{cluster_id}",
          level: level,
          label: parsed["label"] || "グループ#{cluster_id}",
          description: parsed["description"] || ""
        )
      rescue JSON::ParserError
        default_label(level, cluster_id)
      end

      def default_label(level, cluster_id)
        ClusterLabel.default(level, cluster_id)
      end
    end
  end
end
