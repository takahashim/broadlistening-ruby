# frozen_string_literal: true

require "erubi"
require "json"

module Broadlistening
  module Html
    # Renders PipelineResult as HTML for preview and review.
    #
    # This class generates a standalone HTML page with:
    # - A Plotly.js scatter plot visualizing arguments
    # - An overview section with the pipeline summary
    # - A list of level 1 clusters with their labels and takeaways
    #
    # @example Basic usage
    #   result = pipeline.run(comments)
    #   renderer = Html::Renderer.new(result)
    #   renderer.save("report.html")
    #
    # @example With custom options
    #   renderer = Html::Renderer.new(result, title: "My Analysis", template: "custom.html.erb")
    #   html = renderer.render
    #
    class Renderer
      COLORS = %w[
        #1f77b4 #ff7f0e #2ca02c #d62728 #9467bd
        #8c564b #e377c2 #7f7f7f #bcbd22 #17becf
      ].freeze

      attr_reader :result, :title

      # Create a renderer from a hierarchical_result.json file
      #
      # @param json_path [String, Pathname] Path to the JSON file
      # @param options [Hash] Rendering options (same as initialize)
      # @return [Renderer]
      def self.from_json(json_path, options = {})
        data = JSON.parse(File.read(json_path), symbolize_names: true)
        result = build_result_from_json(data)
        new(result, options)
      end

      # Build a PipelineResult from parsed JSON data
      #
      # @param data [Hash] Parsed JSON data
      # @return [PipelineResult]
      def self.build_result_from_json(data)
        arguments = (data[:arguments] || []).map do |arg|
          PipelineResult::Argument.new(
            arg_id: arg[:arg_id],
            argument: arg[:argument],
            comment_id: arg[:comment_id],
            x: arg[:x],
            y: arg[:y],
            p: arg[:p] || 0,
            cluster_ids: arg[:cluster_ids] || [],
            attributes: arg[:attributes],
            url: arg[:url]
          )
        end

        clusters = (data[:clusters] || []).map do |c|
          PipelineResult::Cluster.new(
            level: c[:level],
            id: c[:id],
            label: c[:label],
            takeaway: c[:takeaway],
            value: c[:value],
            parent: c[:parent],
            density_rank_percentile: c[:density_rank_percentile]
          )
        end

        comments = (data[:comments] || {}).transform_values do |c|
          PipelineResult::Comment.new(comment: c[:comment])
        end

        PipelineResult.new(
          arguments: arguments,
          clusters: clusters,
          comments: comments,
          property_map: data[:propertyMap] || {},
          translations: data[:translations] || {},
          overview: data[:overview] || "",
          config: data[:config] || {},
          comment_num: data[:comment_num] || arguments.size
        )
      end

      # Initialize the renderer
      #
      # @param result [PipelineResult] The pipeline result to render
      # @param options [Hash] Rendering options
      # @option options [String] :title Page title (default: "分析結果")
      # @option options [String] :template Path to custom ERB template
      def initialize(result, options = {})
        @result = result
        @title = options[:title] || "分析結果"
        @template_path = options[:template] || default_template_path
      end

      # Render the HTML
      #
      # @return [String] The rendered HTML
      def render
        template = Erubi::Engine.new(File.read(@template_path), escape: true)
        eval(template.src, binding, @template_path) # rubocop:disable Security/Eval
      end

      # Save the rendered HTML to a file
      #
      # @param output_path [String, Pathname] The path to save the HTML
      # @return [void]
      def save(output_path)
        File.write(output_path, render)
      end

      # Get level 1 clusters only
      #
      # @return [Array<PipelineResult::Cluster>] Level 1 clusters sorted by value (descending)
      def level1_clusters
        @level1_clusters ||= result.clusters
          .select { |c| c.level == 1 }
          .sort_by { |c| -c.value }
      end

      # Get cluster color by ID
      #
      # @param cluster_id [String] The cluster ID (e.g., "1_0")
      # @return [String] Hex color code
      def cluster_color(cluster_id)
        return COLORS[0] unless cluster_id&.include?("_")

        index = cluster_id.split("_").last.to_i
        COLORS[index % COLORS.size]
      end

      # Generate JSON for Plotly points
      #
      # @return [String] JSON array of point data
      def points_json
        points = result.arguments.map do |arg|
          {
            arg_id: arg.arg_id,
            argument: arg.argument,
            x: arg.x,
            y: arg.y,
            cluster_id: arg.cluster_ids[1] || arg.cluster_ids[0]
          }
        end
        JSON.generate(points)
      end

      # Generate cluster metadata JSON for Plotly annotations
      #
      # @return [String] JSON object of cluster metadata
      def cluster_meta_json
        meta = level1_clusters.each_with_object({}) do |cluster, hash|
          hash[cluster.id] = {
            label: cluster.label,
            color: cluster_color(cluster.id)
          }
        end
        JSON.generate(meta)
      end

      # Generate JSON for all clusters (for subclusters navigation)
      #
      # @return [String] JSON object of all cluster data
      def all_clusters_json
        clusters = result.clusters.map do |c|
          {
            id: c.id,
            level: c.level,
            label: c.label,
            takeaway: c.takeaway,
            value: c.value,
            parent: c.parent,
            color: cluster_color(c.id)
          }
        end
        JSON.generate(clusters)
      end

      # Generate JSON for all points with full cluster_ids
      #
      # @return [String] JSON array of point data with all cluster_ids
      def full_points_json
        points = result.arguments.map do |arg|
          {
            arg_id: arg.arg_id,
            argument: arg.argument,
            x: arg.x,
            y: arg.y,
            cluster_ids: arg.cluster_ids
          }
        end
        JSON.generate(points)
      end

      private

      def default_template_path
        File.expand_path("templates/report.html.erb", __dir__)
      end
    end
  end
end
