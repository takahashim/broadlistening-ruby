# frozen_string_literal: true

require "json"

module Broadlistening
  class Config
    attr_reader :model, :embedding_model, :provider, :cluster_nums, :workers, :prompts, :api_key,
                :enable_source_link, :hidden_properties, :is_pubcom,
                :api_base_url, :local_llm_address, :azure_api_version

    DEFAULT_CLUSTER_NUMS = [ 5, 15 ].freeze
    DEFAULT_WORKERS = 10
    DEFAULT_AZURE_API_VERSION = "2024-02-15-preview"

    def self.from_json(json_string)
      data = JSON.parse(json_string, symbolize_names: true)
      from_hash(data)
    end

    def self.from_hash(hash)
      prompts = hash[:prompts]&.transform_keys(&:to_sym)

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

    def self.from_file(path)
      from_json(File.read(path))
    end

    def initialize(options = {})
      @local_llm_address = options[:local_llm_address] || ENV.fetch("LOCAL_LLM_ADDRESS", "localhost:11434")
      @provider_obj = Provider.new(
        options[:provider] || "openai",
        local_llm_address: @local_llm_address
      )
      @provider = @provider_obj.name
      @model = options[:model] || @provider_obj.default_model
      @embedding_model = options[:embedding_model] || @provider_obj.default_embedding_model
      @cluster_nums = options[:cluster_nums] || DEFAULT_CLUSTER_NUMS.dup
      @workers = options[:workers] || DEFAULT_WORKERS
      @prompts = default_prompts.merge(options[:prompts] || {})
      @api_key = options[:api_key] || @provider_obj.api_key
      @enable_source_link = options.fetch(:enable_source_link, false)
      @hidden_properties = options.fetch(:hidden_properties, {}) || {}
      @is_pubcom = options.fetch(:is_pubcom, false)
      @api_base_url = options[:api_base_url] || @provider_obj.base_url
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

    def to_json(*args)
      to_h.merge(prompts: prompts).to_json(*args)
    end

    def save_to_file(path)
      File.write(path, JSON.pretty_generate(to_h.merge(prompts: prompts)))
    end

    def property_names
      hidden_properties.keys
    end

    private

    def validate!
      if @provider_obj.requires_api_key? && (api_key.nil? || api_key.empty?)
        raise ConfigurationError, "API key is required"
      end
      if @provider_obj.requires_base_url? && (api_base_url.nil? || api_base_url.empty?)
        raise ConfigurationError, "Azure requires api_base_url"
      end
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
