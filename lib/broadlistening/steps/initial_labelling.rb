# frozen_string_literal: true

module Broadlistening
  module Steps
    class InitialLabelling < BaseStep
      SAMPLING_NUM = 30

      def execute
        arguments = context[:arguments]
        cluster_results = context[:cluster_results]
        return context.merge(initial_labels: {}) if arguments.empty? || cluster_results.empty?

        max_level = cluster_results.keys.max
        cluster_ids = cluster_results[max_level].uniq

        labels = label_clusters_in_parallel(arguments, max_level, cluster_ids)

        context.merge(
          initial_labels: labels.to_h { |l| [l[:cluster_id], l] }
        )
      end

      private

      def label_clusters_in_parallel(arguments, level, cluster_ids)
        total = cluster_ids.size
        mutex = Mutex.new
        processed = 0

        Parallel.map(cluster_ids, in_threads: config.workers) do |cluster_id|
          result = label_single_cluster(arguments, level, cluster_id)
          current = mutex.synchronize { processed += 1 }
          notify_progress(current: current, total: total)
          result
        end
      end

      def label_single_cluster(arguments, level, cluster_id)
        cluster_args = filter_arguments_by_cluster(arguments, level, cluster_id)
        sampled = sample_arguments(cluster_args)

        input = sampled.map { |a| a[:argument] }.join("\n")

        response = llm_client.chat(
          system: config.prompts[:initial_labelling],
          user: input,
          json_mode: true
        )

        parse_label_response(response, level, cluster_id)
      rescue StandardError => e
        warn "Failed to label cluster #{level}_#{cluster_id}: #{e.message}"
        default_label(level, cluster_id)
      end

      def filter_arguments_by_cluster(arguments, level, cluster_id)
        target_cluster_id = "#{level}_#{cluster_id}"
        arguments.select { |arg| arg[:cluster_ids].include?(target_cluster_id) }
      end

      def sample_arguments(cluster_args)
        sample_size = [SAMPLING_NUM, cluster_args.size].min
        cluster_args.sample(sample_size)
      end

      def parse_label_response(response, level, cluster_id)
        parsed = JSON.parse(response)
        {
          cluster_id: "#{level}_#{cluster_id}",
          level: level,
          label: parsed["label"] || "グループ#{cluster_id}",
          description: parsed["description"] || ""
        }
      rescue JSON::ParserError
        default_label(level, cluster_id)
      end

      def default_label(level, cluster_id)
        {
          cluster_id: "#{level}_#{cluster_id}",
          level: level,
          label: "グループ#{cluster_id}",
          description: ""
        }
      end
    end
  end
end
