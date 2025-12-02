# frozen_string_literal: true

module Broadlistening
  class LlmClient
    ChatResult = Data.define(:content, :token_usage)

    MAX_RETRIES = 3
    RETRY_BASE_INTERVAL = 3.0
    RETRY_MAX_INTERVAL = 20.0
    RETRY_MULTIPLIER = 3.0

    RETRIABLE_ERRORS = [
      Faraday::ServerError,
      Faraday::ConnectionFailed,
      Faraday::TimeoutError,
      Net::OpenTimeout,
      Errno::ECONNRESET
    ].freeze

    def initialize(config)
      @config = config
      @provider = Provider.new(config.provider, local_llm_address: config.local_llm_address)
      @client = @provider.build_openai_client(
        api_key: config.api_key,
        base_url: config.api_base_url,
        azure_api_version: config.azure_api_version
      )
    end

    def chat(system:, user:, json_mode: false)
      params = build_chat_params(system, user, json_mode)
      response = with_retry { @client.chat(parameters: params) }
      validate_response!(response)

      ChatResult.new(
        content: response.dig("choices", 0, "message", "content"),
        token_usage: TokenUsage.from_response(response)
      )
    end

    def embed(texts)
      texts = [ texts ] if texts.is_a?(String)
      response = with_retry do
        @client.embeddings(
          parameters: {
            model: @config.embedding_model,
            input: texts
          }
        )
      end
      validate_response!(response)
      response["data"].sort_by { |d| d["index"] }.map { |d| d["embedding"] }
    end

    private

    def build_chat_params(system, user, json_mode)
      params = {
        model: @config.model,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user }
        ]
      }
      params[:response_format] = { type: "json_object" } if json_mode
      params
    end

    def validate_response!(response)
      return if response.is_a?(Hash) && !response["error"]

      error_message = response.is_a?(Hash) ? response.dig("error", "message") : "Unknown error"
      raise LlmError, "LLM API error: #{error_message}"
    end

    def with_retry(&block)
      Retriable.retriable(
        on: RETRIABLE_ERRORS,
        tries: MAX_RETRIES + 1,
        base_interval: RETRY_BASE_INTERVAL,
        max_interval: RETRY_MAX_INTERVAL,
        multiplier: RETRY_MULTIPLIER,
        rand_factor: 0.5
      ) do
        begin
          block.call
        rescue Faraday::ClientError => e
          if rate_limit_error?(e)
            raise Faraday::ServerError, e.message
          end
          raise LlmError, "LLM API error: #{e.message}"
        end
      end
    rescue *RETRIABLE_ERRORS => e
      raise LlmError, "LLM API request failed after #{MAX_RETRIES} retries: #{e.message}"
    end

    def rate_limit_error?(error)
      error.message.include?("429") ||
        error.message.downcase.include?("rate limit") ||
        error.message.downcase.include?("too many requests")
    end
  end
end
