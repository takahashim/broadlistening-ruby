# frozen_string_literal: true

require "json"

module Broadlistening
  class Config
    attr_reader :model, :embedding_model, :provider, :cluster_nums, :workers, :prompts, :api_key,
                :enable_source_link, :hidden_properties, :is_pubcom,
                :api_base_url, :local_llm_address, :azure_api_version

    DEFAULT_MODEL = "gpt-4o-mini"
    DEFAULT_EMBEDDING_MODEL = "text-embedding-3-small"
    DEFAULT_PROVIDER = "openai"
    DEFAULT_CLUSTER_NUMS = [ 5, 15 ].freeze
    DEFAULT_WORKERS = 10
    DEFAULT_LOCAL_LLM_ADDRESS = "localhost:11434"
    DEFAULT_AZURE_API_VERSION = "2024-02-15-preview"

    # プロバイダー別のURI設定
    PROVIDER_URI_BASE = {
      "gemini" => "https://generativelanguage.googleapis.com/v1beta/openai/",
      "openrouter" => "https://openrouter.ai/api/v1"
    }.freeze

    # サポートされているプロバイダー一覧
    SUPPORTED_PROVIDERS = %w[openai azure gemini openrouter local].freeze

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
        api_key: hash[:api_key],
        model: hash[:model],
        embedding_model: hash[:embedding_model],
        provider: hash[:provider],
        cluster_nums: cluster_nums,
        workers: workers,
        prompts: prompts,
        enable_source_link: hash[:enable_source_link],
        hidden_properties: hidden_properties,
        is_pubcom: hash[:is_pubcom],
        api_base_url: hash[:api_base_url],
        local_llm_address: hash[:local_llm_address],
        azure_api_version: hash[:azure_api_version]
      )
    end

    # JSONファイルからConfigを生成
    def self.from_file(path)
      from_json(File.read(path))
    end

    def initialize(options = {})
      @provider = options[:provider] || DEFAULT_PROVIDER
      @model = options[:model] || default_model_for_provider
      @embedding_model = options[:embedding_model] || default_embedding_model_for_provider
      @cluster_nums = options[:cluster_nums] || DEFAULT_CLUSTER_NUMS.dup
      @workers = options[:workers] || DEFAULT_WORKERS
      @prompts = default_prompts.merge(options[:prompts] || {})
      @api_key = options[:api_key] || api_key_from_env
      @enable_source_link = options.fetch(:enable_source_link, false)
      @hidden_properties = options.fetch(:hidden_properties, {}) || {}
      @is_pubcom = options.fetch(:is_pubcom, false)
      @api_base_url = options[:api_base_url] || api_base_url_from_env
      @local_llm_address = options[:local_llm_address] || ENV.fetch("LOCAL_LLM_ADDRESS", DEFAULT_LOCAL_LLM_ADDRESS)
      @azure_api_version = options[:azure_api_version] || ENV.fetch("AZURE_API_VERSION", DEFAULT_AZURE_API_VERSION)

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
        is_pubcom: is_pubcom,
        api_base_url: api_base_url,
        local_llm_address: local_llm_address,
        azure_api_version: azure_api_version
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
      raise ConfigurationError, "Unknown provider: #{provider}" unless SUPPORTED_PROVIDERS.include?(provider)
      raise ConfigurationError, "API key is required" if provider != "local" && (api_key.nil? || api_key.empty?)
      raise ConfigurationError, "Azure requires api_base_url" if provider == "azure" && (api_base_url.nil? || api_base_url.empty?)
      raise ConfigurationError, "cluster_nums must have at least 2 levels" if cluster_nums.size < 2
      raise ConfigurationError, "cluster_nums must be sorted ascending" unless cluster_nums == cluster_nums.sort
    end

    def api_key_from_env
      case @provider
      when "openai" then ENV.fetch("OPENAI_API_KEY", nil)
      when "azure" then ENV.fetch("AZURE_OPENAI_API_KEY", nil)
      when "gemini" then ENV.fetch("GEMINI_API_KEY", nil)
      when "openrouter" then ENV.fetch("OPENROUTER_API_KEY", nil)
      when "local" then "not-needed"
      end
    end

    def api_base_url_from_env
      case @provider
      when "azure" then ENV.fetch("AZURE_OPENAI_URI", nil)
      when "gemini" then PROVIDER_URI_BASE["gemini"]
      when "openrouter" then PROVIDER_URI_BASE["openrouter"]
      when "local" then "http://#{@local_llm_address || DEFAULT_LOCAL_LLM_ADDRESS}/v1"
      end
    end

    def default_model_for_provider
      case @provider
      when "gemini" then "gemini-2.0-flash"
      else DEFAULT_MODEL
      end
    end

    def default_embedding_model_for_provider
      case @provider
      when "gemini" then "text-embedding-004"
      else DEFAULT_EMBEDDING_MODEL
      end
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
