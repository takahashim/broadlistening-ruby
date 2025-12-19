# frozen_string_literal: true

require "json"

module Broadlistening
  class Config
    attr_reader :model, :embedding_model, :provider, :cluster_nums, :workers, :prompts, :api_key,
                :enable_source_link, :hidden_properties, :is_pubcom,
                :api_base_url, :local_llm_address, :azure_api_version,
                :input, :question, :name, :intro, :limit

    DEFAULT_CLUSTER_NUMS = [ 5, 15 ].freeze
    DEFAULT_WORKERS = 10
    DEFAULT_LIMIT = 1000
    DEFAULT_AZURE_API_VERSION = "2024-02-15-preview"

    def self.from_json(json_string)
      data = JSON.parse(json_string, symbolize_names: true)
      from_hash(data)
    end

    def self.from_hash(hash)
      prompts = hash[:prompts]&.transform_keys(&:to_sym)

      cluster_nums = hash[:cluster_nums] || hash.dig(:hierarchical_clustering, :cluster_nums)
      workers = hash[:workers] || hash.dig(:extraction, :workers)
      limit = hash[:limit] || hash.dig(:extraction, :limit)
      # Python uses hierarchical_aggregation.hidden_properties
      hidden_properties = hash[:hidden_properties] ||
                          hash.dig(:hierarchical_aggregation, :hidden_properties) ||
                          hash.dig(:aggregation, :hidden_properties)

      new(
        api_key: hash[:api_key],
        model: hash[:model],
        embedding_model: hash[:embedding_model],
        provider: hash[:provider],
        cluster_nums: cluster_nums,
        workers: workers,
        limit: limit,
        prompts: prompts,
        enable_source_link: hash[:enable_source_link],
        hidden_properties: hidden_properties,
        is_pubcom: hash[:is_pubcom],
        api_base_url: hash[:api_base_url],
        local_llm_address: hash[:local_llm_address],
        azure_api_version: hash[:azure_api_version],
        input: hash[:input],
        question: hash[:question],
        name: hash[:name],
        intro: hash[:intro]
      )
    end

    def self.from_file(path)
      from_json(File.read(path))
    end

    def initialize(options = {})
      @local_llm_address = options[:local_llm_address] || ENV.fetch("LOCAL_LLM_ADDRESS", "localhost:11434")
      @provider_obj = Provider.new(
        options[:provider]&.to_sym || :openai,
        local_llm_address: @local_llm_address
      )
      @provider = @provider_obj.name
      @model = options[:model] || @provider_obj.default_model
      @embedding_model = options[:embedding_model] || @provider_obj.default_embedding_model
      @cluster_nums = options[:cluster_nums] || DEFAULT_CLUSTER_NUMS.dup
      @workers = options[:workers] || DEFAULT_WORKERS
      @limit = options[:limit] || DEFAULT_LIMIT
      @prompts = default_prompts.merge(options[:prompts] || {})
      @api_key = options[:api_key] || @provider_obj.api_key
      @enable_source_link = options[:enable_source_link].nil? ? false : options[:enable_source_link]
      @hidden_properties = options.fetch(:hidden_properties, {}) || {}
      @is_pubcom = options[:is_pubcom].nil? ? false : options[:is_pubcom]
      @api_base_url = options[:api_base_url] || @provider_obj.base_url
      @azure_api_version = options[:azure_api_version] || ENV.fetch("AZURE_API_VERSION", DEFAULT_AZURE_API_VERSION)
      @input = options[:input]
      @question = options[:question]
      @name = options[:name]
      @intro = options[:intro]

      validate!
    end

    def to_h
      {
        model: model,
        embedding_model: embedding_model,
        provider: provider,
        cluster_nums: cluster_nums,
        workers: workers,
        limit: limit,
        enable_source_link: enable_source_link,
        hidden_properties: hidden_properties,
        is_pubcom: is_pubcom,
        api_base_url: api_base_url,
        local_llm_address: local_llm_address,
        azure_api_version: azure_api_version,
        input: input,
        question: question,
        name: name,
        intro: intro
      }.compact
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
        あなたは専門的なリサーチアシスタントです。与えられたテキストから、意見を抽出して整理してください。

        # 指示
        * 入出力の例に記載したような形式で文字列のリストを返してください
          * 必要な場合は2つの別個の意見に分割してください。多くの場合は1つの議論にまとめる方が望ましいです。
        * 整理した意見は日本語で出力してください

        ## 入出力の例
        /human

        AIテクノロジーは、そのライフサイクル全体における環境負荷を削減することに焦点を当てて開発されるべきです。

        /ai

        {
          "extractedOpinionList": [
            "AIテクノロジーは、そのライフサイクル全体における環境負荷を削減することに焦点を当てて開発されるべきです。"
          ]
        }

        /human

        AIの能力、限界、倫理的考慮事項について、市民を教育する必要がある。また、教育できる人材を養成する必要がある。

        /ai

        {
          "extractedOpinionList": [
            "AIの能力、限界、倫理的考慮事項について、市民を教育すべき",
            "AIに関する教育をできる人材を養成すべき"
          ]
        }

        /human

        AIはエネルギーグリッドを最適化し、無駄や炭素排出を削減できます。

        /ai

        {
          "extractedOpinionList": [
            "AIはエネルギーグリッドを最適化して炭素排出を削減できる"
          ]
        }
      PROMPT
    end

    def initial_labelling_prompt
      <<~PROMPT
        あなたはKJ法が得意なデータ分析者です。userのinputはグループに集まったラベルです。なぜそのラベルが一つのグループであるか解説し、表札（label）をつけてください。
        表札については、グループ内の具体的な論点や特徴を反映した、具体性の高い名称を考案してください。
        出力はJSONとし、フォーマットは以下のサンプルを参考にしてください。


        # サンプルの入出力
        ## 入力例
        - 手作業での意見分析は時間がかかりすぎる。AIで効率化できると嬉しい
        - 今のやり方だと分析に工数がかかりすぎるけど、AIならコストをかけずに分析できそう
        - AIが自動で意見を整理してくれると楽になって嬉しい


        ## 出力例
        {
            "label": "AIによる業務効率の大幅向上とコスト効率化",
            "description": "この意見グループは、従来の手作業による意見分析と比較して、AIによる自動化で分析プロセスが効率化され、作業時間の短縮や運用コストの効率化が実現される点に対する前向きな評価が中心です。"
        }
      PROMPT
    end

    def merge_labelling_prompt
      <<~PROMPT
        あなたはデータ分析のエキスパートです。
        現在、テキストデータの階層クラスタリングを行っています。
        下層のクラスタ（意見グループ）のタイトルと説明、およびそれらのクラスタが所属する上層のクラスタのテキストのサンプルを与えるので、上層のクラスタのタイトルと説明を作成してください。

        # 指示
        - 統合後のクラスタ名は、統合前のクラスタ名称をそのまま引用せず、内容に基づいた新たな名称にしてください。
        - タイトルには、具体的な事象・行動（例：地域ごとの迅速対応、復興計画の着実な進展、効果的な情報共有・地域協力など）を含めてください
          - 可能な限り具体的な表現を用いるようにし、抽象的な表現は避けてください
            - 「多様な意見」などの抽象的な表現は避けてください
        - 出力例に示したJSON形式で出力してください


        # サンプルの入出力
        ## 入力例
        - 「顧客フィードバックの自動集約」: この意見グループは、SNSやオンラインレビューなどから集めた大量の意見をAIが瞬時に解析し、企業が市場のトレンドや顧客の要望を即時に把握できる点についての期待を示しています。
        - 「AIによる業務効率の大幅向上とコスト効率化」: この意見グループは、従来の手作業による意見分析と比較して、AIによる自動化で分析プロセスが効率化され、作業時間の短縮や運用コストの効率化が実現される点に対する前向きな評価が中心です。

        ## 出力例
        {
            "label": "AI技術の導入による意見分析の効率化への期待",
            "description": "大量の意見やフィードバックから迅速に洞察を抽出できるため、企業や自治体が消費者や市民の声を的確に把握し、戦略的な意思決定やサービス改善が可能になります。また、従来の手法と比べて作業負荷が軽減され、業務効率の向上やコスト削減といった実際の便益が得られると期待されています。"
        }
      PROMPT
    end

    def overview_prompt
      <<~PROMPT
        あなたはシンクタンクで働く専門のリサーチアシスタントです。
        チームは特定のテーマに関してパブリック・コンサルテーションを実施し、異なる選択肢の意見グループを分析し始めています。
        これから意見グループのリストとその簡単な分析が提供されます。
        あなたの仕事は、調査結果の簡潔な要約を返すことです。要約は非常に簡潔に（最大で1段落、最大4文）まとめ、無意味な言葉を避けてください。
        出力は日本語で行ってください。
      PROMPT
    end
  end
end
