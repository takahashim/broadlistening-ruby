# frozen_string_literal: true

module Broadlistening
  module Steps
    class Aggregation < BaseStep
      # Output format compatible with Kouchou-AI Python implementation
      def execute
        result = {
          arguments: build_arguments,
          clusters: build_clusters,
          comments: build_comments,
          propertyMap: build_property_map,
          translations: build_translations,
          overview: context[:overview],
          config: config.to_h,
          comment_num: context[:comments].size
        }

        context.merge(result: result)
      end

      private

      def build_arguments
        context[:arguments].map do |arg|
          build_single_argument(arg)
        end
      end

      def build_single_argument(arg)
        result = {
          arg_id: arg[:arg_id],
          argument: arg[:argument],
          comment_id: extract_comment_id(arg),
          x: arg[:x]&.to_f,
          y: arg[:y]&.to_f,
          p: 0, # Reserved for future confidence scoring
          cluster_ids: arg[:cluster_ids]
        }

        # TODO: Add attributes support when input has attribute_* columns
        # result[:attributes] = arg[:attributes] if arg[:attributes]

        # TODO: Add url support when enable_source_link config is true
        # result[:url] = arg[:url] if config.enable_source_link && arg[:url]

        result
      end

      def extract_comment_id(arg)
        # comment_id can be stored directly or extracted from arg_id (A{comment_id}_{index})
        return arg[:comment_id].to_i if arg[:comment_id]

        # Fallback: extract from arg_id format "A{comment_id}_{index}"
        match = arg[:arg_id]&.match(/\AA(\d+)_/)
        match ? match[1].to_i : 0
      end

      def build_clusters
        clusters = [root_cluster]

        context[:labels].each_value do |label|
          clusters << {
            level: label[:level],
            id: label[:cluster_id],
            label: label[:label],
            takeaway: label[:description] || "",
            value: count_arguments_in_cluster(label[:cluster_id]),
            parent: find_parent_cluster(label),
            density_rank_percentile: nil # TODO: Implement density calculation
          }
        end

        clusters.sort_by { |c| [c[:level], c[:id]] }
      end

      def root_cluster
        {
          level: 0,
          id: "0",
          label: "全体",
          takeaway: "",
          value: context[:arguments].size,
          parent: "",
          density_rank_percentile: nil
        }
      end

      def count_arguments_in_cluster(cluster_id)
        context[:arguments].count { |a| a[:cluster_ids].include?(cluster_id) }
      end

      def find_parent_cluster(label)
        return "0" if label[:level] == 1

        parent_level = label[:level] - 1
        cluster_results = context[:cluster_results]

        # Find an argument that belongs to this cluster
        arg_idx = context[:arguments].index { |a| a[:cluster_ids].include?(label[:cluster_id]) }
        return "0" unless arg_idx

        parent_cluster_num = cluster_results[parent_level][arg_idx]
        "#{parent_level}_#{parent_cluster_num}"
      end

      def build_comments
        # Build comments object keyed by comment_id
        # Only includes comments that have extracted arguments
        comments_with_args = Set.new
        context[:arguments].each do |arg|
          comment_id = extract_comment_id(arg)
          comments_with_args.add(comment_id)
        end

        result = {}
        context[:comments].each do |comment|
          comment_id = comment[:id].to_i
          next unless comments_with_args.include?(comment_id)

          result[comment_id.to_s] = {
            comment: comment[:body]
          }
        end

        result
      end

      def build_property_map
        # TODO: Implement propertyMap when hidden_properties and classification categories are supported
        # Returns mapping of property_name => { arg_id => value, ... }
        {}
      end

      def build_translations
        # TODO: Implement translations when translation feature is enabled
        # Returns translations loaded from translations.json if enabled
        {}
      end
    end
  end
end
