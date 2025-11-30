# frozen_string_literal: true

require "csv"

module Broadlistening
  module Steps
    class Aggregation < BaseStep
      CSV_FILENAME = "final_result_with_comments.csv"

      # Output format compatible with Kouchou-AI Python implementation
      def execute
        result = {
          arguments: build_arguments,
          clusters: build_clusters,
          comments: build_comments,
          propertyMap: build_property_map,
          translations: build_translations,
          overview: context.overview,
          config: config.to_h,
          comment_num: context.comments.size
        }

        context.result = result

        export_csv if config.is_pubcom && context.output_dir

        context
      end

      private

      def build_arguments
        context.arguments.map do |arg|
          build_single_argument(arg)
        end
      end

      def build_single_argument(arg)
        result = {
          arg_id: arg.arg_id,
          argument: arg.argument,
          comment_id: arg.comment_id_int,
          x: arg.x&.to_f,
          y: arg.y&.to_f,
          p: 0,
          cluster_ids: arg.cluster_ids
        }

        result[:attributes] = arg.attributes if arg.attributes
        result[:url] = arg.url if config.enable_source_link && arg.url

        result
      end

      def build_clusters
        clusters = [ root_cluster ]
        density_data = calculate_density_data

        context.labels.each_value do |label|
          cluster_id = label[:cluster_id]
          density_info = density_data[cluster_id]

          clusters << {
            level: label[:level],
            id: cluster_id,
            label: label[:label],
            takeaway: label[:description] || "",
            value: count_arguments_in_cluster(cluster_id),
            parent: find_parent_cluster(label),
            density_rank_percentile: density_info&.dig(:density_rank_percentile)
          }
        end

        clusters.sort_by { |c| [ c[:level], c[:id] ] }
      end

      def calculate_density_data
        return {} if context.arguments.empty?

        # Build cluster data structure for density calculation
        cluster_data = {}

        context.labels.each_value do |label|
          cluster_id = label[:cluster_id]
          points = context.arguments.select { |arg| arg.in_cluster?(cluster_id) }
                                    .map { |arg| [ arg.x, arg.y ] }
                                    .reject { |p| p.any?(&:nil?) }

          next if points.empty?

          cluster_data[cluster_id] = {
            points: points,
            level: label[:level]
          }
        end

        return {} if cluster_data.empty?

        DensityCalculator.calculate_with_ranks(cluster_data)
      end

      def root_cluster
        {
          level: 0,
          id: "0",
          label: "全体",
          takeaway: "",
          value: context.arguments.size,
          parent: "",
          density_rank_percentile: nil
        }
      end

      def count_arguments_in_cluster(cluster_id)
        context.arguments.count { |arg| arg.in_cluster?(cluster_id) }
      end

      def find_parent_cluster(label)
        return "0" if label[:level] == 1

        parent_level = label[:level] - 1

        # Find an argument that belongs to this cluster
        arg_idx = context.arguments.index { |arg| arg.in_cluster?(label[:cluster_id]) }
        return "0" unless arg_idx

        parent_cluster_num = context.cluster_results[parent_level][arg_idx]
        "#{parent_level}_#{parent_cluster_num}"
      end

      def build_comments
        comments_with_args = Set.new
        context.arguments.each do |arg|
          comments_with_args.add(arg.comment_id_int)
        end

        result = {}
        context.comments.each do |comment|
          comment_id = comment.id.to_i
          next unless comments_with_args.include?(comment_id)

          result[comment_id.to_s] = { comment: comment.body }
        end

        result
      end

      def build_property_map
        return {} if config.property_names.empty?

        property_map = {}
        config.property_names.each do |prop_name|
          property_map[prop_name.to_s] = {}
        end

        context.arguments.each do |arg|
          next unless arg.properties

          arg.properties.each do |prop_name, value|
            property_map[prop_name.to_s] ||= {}
            property_map[prop_name.to_s][arg.arg_id] = normalize_property_value(value)
          end
        end

        property_map
      end

      def normalize_property_value(value)
        return nil if value.nil?

        case value
        when Integer, Float, String, TrueClass, FalseClass
          value
        when Array
          value.map { |v| normalize_property_value(v) }
        else
          value.to_s
        end
      end

      def build_translations
        {}
      end

      # Export CSV with original comments for pubcom mode
      def export_csv
        csv_path = Pathname.new(context.output_dir) / CSV_FILENAME
        level1_labels = build_level1_label_map

        CSV.open(csv_path, "w", encoding: "UTF-8") do |csv|
          csv << csv_headers
          context.arguments.each do |arg|
            csv << build_csv_row(arg, level1_labels)
          end
        end
      end

      def csv_headers
        headers = %w[comment_id original_comment arg_id argument category_id category x y]
        headers += attribute_columns
        headers
      end

      def build_csv_row(arg, level1_labels)
        comment = find_comment(arg.comment_id)
        level1_cluster_id = find_level1_cluster_id(arg)
        category_label = level1_labels[level1_cluster_id] || ""

        row = [
          arg.comment_id,
          comment&.body || "",
          arg.arg_id,
          arg.argument,
          level1_cluster_id,
          category_label,
          arg.x,
          arg.y
        ]

        # Add attribute values
        attribute_columns.each do |attr_name|
          row << (arg.attributes&.dig(attr_name.sub(/^attribute_/, "")) || comment&.attributes&.dig(attr_name.sub(/^attribute_/, "")))
        end

        row
      end

      def build_level1_label_map
        context.labels
          .select { |_, label| label[:level] == 1 }
          .transform_values { |label| label[:label] }
          .transform_keys(&:to_s)
      end

      def find_level1_cluster_id(arg)
        arg.cluster_ids&.find { |id| id.start_with?("1_") } || ""
      end

      def find_comment(comment_id)
        context.comments.find { |c| c.id.to_s == comment_id.to_s }
      end

      def attribute_columns
        @attribute_columns ||= begin
          attrs = Set.new
          context.arguments.each do |arg|
            arg.attributes&.each_key { |k| attrs.add("attribute_#{k}") }
          end
          context.comments.each do |comment|
            comment.attributes&.each_key { |k| attrs.add("attribute_#{k}") }
          end
          attrs.to_a.sort
        end
      end
    end
  end
end
