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

    def chat(system:, user:, json_mode: false, json_schema: nil)
      params = build_chat_params(system, user, json_mode, json_schema)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = with_retry { @client.chat(parameters: params) }
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

      validate_response!(response)

      token_usage = TokenUsage.from_response(response)
      notify_llm_call(token_usage: token_usage, duration_ms: duration_ms)

      ChatResult.new(
        content: response.dig("choices", 0, "message", "content"),
        token_usage: token_usage
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
      extract_embeddings(response["data"])
    end

    private

    def extract_embeddings(data)
      # Sort by index if available (OpenAI), otherwise preserve order (Gemini)
      sorted = if data.first&.key?("index")
                 data.sort_by { |d| d["index"] }
      else
                 data
      end
      sorted.map { |d| d["embedding"] }
    end

    def build_chat_params(system, user, json_mode, json_schema)
      params = {
        model: @config.model,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user }
        ]
      }
      if json_schema
        # Structured Outputs: Use JSON schema for strict response format
        params[:response_format] = {
          type: "json_schema",
          json_schema: json_schema
        }
      elsif json_mode
        # Simple JSON mode: requires "JSON" in prompt
        params[:response_format] = { type: "json_object" }
      end

      # OpenRouter: Enable response-healing plugin for JSON responses
      # This automatically fixes malformed JSON (missing brackets, commas, quotes, etc.)
      if @provider.openrouter? && (json_schema || json_mode)
        params[:plugins] = [ { id: "response-healing" } ]
      end

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

    def notify_llm_call(token_usage:, duration_ms:)
      ActiveSupport::Notifications.instrument("llm.broadlistening", {
        token_usage: token_usage,
        duration_ms: duration_ms
      })
    end
  end
end
