# frozen_string_literal: true

require "json"

module Broadlistening
  class Config
    attr_reader :model, :embedding_model, :provider, :cluster_nums, :workers, :prompts, :api_key,
                :enable_source_link, :hidden_properties, :is_pubcom

    DEFAULT_MODEL = "gpt-4o-mini"
    DEFAULT_EMBEDDING_MODEL = "text-embedding-3-small"
    DEFAULT_PROVIDER = "openai"
    DEFAULT_CLUSTER_NUMS = [ 5, 15 ].freeze
    DEFAULT_WORKERS = 10

    # JSON文字列からConfigを生成
    def self.from_json(json_string)
      data = JSON.parse(json_string, symbolize_names: true)
      from_hash(data)
    end

    # Hashからonfigを生成（Python版config.jsonの構造にも対応）
    def self.from_hash(hash)
      # プロンプトのキーをシンボルに変換
      prompts = hash[:prompts]&.transform_keys(&:to_sym)

      # Python版config.jsonのネスト構造にも対応
      cluster_nums = hash[:cluster_nums] || hash.dig(:hierarchical_clustering, :cluster_nums)
      workers = hash[:workers] || hash.dig(:extraction, :workers)
      hidden_properties = hash[:hidden_properties] || hash.dig(:aggregation, :hidden_properties)

      new(
        api_key: hash[:api_key] || ENV.fetch("OPENAI_API_KEY", nil),
        model: hash[:model],
        embedding_model: hash[:embedding_model],
        provider: hash[:provider],
        cluster_nums: cluster_nums,
        workers: workers,
        prompts: prompts,
        enable_source_link: hash[:enable_source_link],
        hidden_properties: hidden_properties,
        is_pubcom: hash[:is_pubcom]
      )
    end

    # JSONファイルからConfigを生成
    def self.from_file(path)
      from_json(File.read(path))
    end

    def initialize(options = {})
      @model = options[:model] || DEFAULT_MODEL
      @embedding_model = options[:embedding_model] || DEFAULT_EMBEDDING_MODEL
      @provider = options[:provider] || DEFAULT_PROVIDER
      @cluster_nums = options[:cluster_nums] || DEFAULT_CLUSTER_NUMS.dup
      @workers = options[:workers] || DEFAULT_WORKERS
      @prompts = default_prompts.merge(options[:prompts] || {})
      @api_key = options[:api_key] || ENV.fetch("OPENAI_API_KEY", nil)
      @enable_source_link = options.fetch(:enable_source_link, false)
      @hidden_properties = options.fetch(:hidden_properties, {}) || {}
      @is_pubcom = options.fetch(:is_pubcom, false)

      validate!
    end

    def to_h
      {
        model: model,
        embedding_model: embedding_model,
        provider: provider,
        cluster_nums: cluster_nums,
        workers: workers,
        enable_source_link: enable_source_link,
        hidden_properties: hidden_properties,
        is_pubcom: is_pubcom
      }
    end

    # JSONへのエクスポート
    def to_json(*args)
      to_h.merge(prompts: prompts).to_json(*args)
    end

    # JSONファイルへの保存
    def save_to_file(path)
      File.write(path, JSON.pretty_generate(to_h.merge(prompts: prompts)))
    end

    # Returns list of property names to include in propertyMap
    def property_names
      hidden_properties.keys
    end

    private

    def validate!
      raise ConfigurationError, "API key is required" if api_key.nil? || api_key.empty?
      raise ConfigurationError, "cluster_nums must have at least 2 levels" if cluster_nums.size < 2
      raise ConfigurationError, "cluster_nums must be sorted ascending" unless cluster_nums == cluster_nums.sort
    end

    def default_prompts
      {
        extraction: extraction_prompt,
        initial_labelling: initial_labelling_prompt,
        merge_labelling: merge_labelling_prompt,
        overview: overview_prompt
      }
    end

    def extraction_prompt
      <<~PROMPT
        あなたは意見抽出の専門家です。
        以下のコメントから、主要な意見や主張を抽出してください。
        1つのコメントに複数の意見が含まれる場合は、それぞれを別々に抽出してください。
        抽出した意見はJSON形式で返してください。

        出力フォーマット:
        {"extractedOpinionList": ["意見1", "意見2", ...]}

        注意:
        - 事実の記述ではなく、意見や主張を抽出してください
        - 曖昧な表現は具体的に言い換えてください
        - 重複する意見は1つにまとめてください
      PROMPT
    end

    def initial_labelling_prompt
      <<~PROMPT
        あなたはクラスタ分析の専門家です。
        以下の意見グループに対して、適切なラベルと説明を付けてください。

        出力フォーマット:
        {"label": "ラベル名", "description": "このグループの説明"}

        注意:
        - ラベルは簡潔で分かりやすいものにしてください（10文字以内推奨）
        - 説明はグループの特徴を端的に表してください（50文字以内推奨）
      PROMPT
    end

    def merge_labelling_prompt
      <<~PROMPT
        あなたはクラスタ分析の専門家です。
        以下の子クラスタのラベルと説明を統合し、親クラスタのラベルと説明を作成してください。

        出力フォーマット:
        {"label": "ラベル名", "description": "このグループの説明"}

        注意:
        - 親ラベルは子ラベルの共通テーマを表すものにしてください
        - 抽象度を上げすぎず、具体性を保ってください
      PROMPT
    end

    def overview_prompt
      <<~PROMPT
        あなたは分析レポートの専門家です。
        以下のクラスタ分析結果に基づいて、全体の概要を作成してください。

        注意:
        - 主要なテーマや傾向を簡潔にまとめてください
        - 200-300文字程度で記述してください
        - 客観的な記述を心がけてください
      PROMPT
    end
  end
end
