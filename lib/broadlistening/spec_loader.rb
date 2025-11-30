# frozen_string_literal: true

require "json"

module Broadlistening
  class SpecLoader
    # Python版のステップ名をRuby gem用に変換するマッピング
    STEP_MAPPING = {
      "extraction" => :extraction,
      "embedding" => :embedding,
      "hierarchical_clustering" => :clustering,
      "hierarchical_initial_labelling" => :initial_labelling,
      "hierarchical_merge_labelling" => :merge_labelling,
      "hierarchical_overview" => :overview,
      "hierarchical_aggregation" => :aggregation,
      "hierarchical_visualization" => nil # スキップ（gem責務外）
    }.freeze

    # Ruby gem独自の中間ファイル名
    OUTPUT_FILES = {
      extraction: "extraction.json",
      embedding: "embeddings.json",
      clustering: "clustering.json",
      initial_labelling: "initial_labels.json",
      merge_labelling: "merge_labels.json",
      overview: "overview.json",
      aggregation: "result.json"
    }.freeze

    attr_reader :specs

    def initialize(specs_path)
      raw_specs = JSON.parse(File.read(specs_path), symbolize_names: true)
      @specs = convert_specs(raw_specs)
    end

    def self.default
      new(default_specs_path)
    end

    def self.default_specs_path
      ENV.fetch("BROADLISTENING_SPECS_PATH") do
        File.expand_path("../../../../../server/broadlistening/pipeline/hierarchical_specs.json", __dir__)
      end
    end

    def find(step_name)
      @specs.find { |s| s[:step] == step_name.to_sym }
    end

    def steps
      @specs.map { |s| s[:step] }
    end

    private

    def convert_specs(raw_specs)
      raw_specs.filter_map do |spec|
        ruby_step = STEP_MAPPING[spec[:step]]
        next if ruby_step.nil? # hierarchical_visualization等をスキップ

        {
          step: ruby_step,
          output_file: OUTPUT_FILES[ruby_step],
          dependencies: convert_dependencies(spec),
          use_llm: spec[:use_llm] || false
        }
      end
    end

    def convert_dependencies(spec)
      deps = spec[:dependencies] || {}
      params = (deps[:params] || []).map(&:to_sym)

      # use_llm が true の場合、prompt と model を自動追加
      if spec[:use_llm]
        params << :prompt unless params.include?(:prompt)
        params << :model unless params.include?(:model)
      end

      steps = (deps[:steps] || []).filter_map { |s| STEP_MAPPING[s] }

      { params: params.uniq, steps: steps }
    end
  end
end
