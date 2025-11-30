# frozen_string_literal: true

module Broadlistening
  class LlmClient
    # Retry configuration matching kouchou-ai Python implementation
    # Python: wait_exponential(multiplier=3, min=3, max=20), stop_after_attempt(3)
    MAX_RETRIES = 3
    RETRY_BASE_INTERVAL = 3.0  # min wait time in seconds
    RETRY_MAX_INTERVAL = 20.0  # max wait time in seconds
    RETRY_MULTIPLIER = 3.0     # exponential multiplier

    # Errors that should trigger retry (transient errors)
    RETRIABLE_ERRORS = [
      Faraday::ServerError,       # 5xx errors
      Faraday::ConnectionFailed,  # Network connection issues
      Faraday::TimeoutError,      # Request timeout
      Net::OpenTimeout,           # Connection timeout
      Errno::ECONNRESET           # Connection reset by peer
    ].freeze

    # Errors that should NOT retry (client errors)
    NON_RETRIABLE_ERRORS = [
      Faraday::ClientError        # 4xx errors (except rate limit)
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
      extract_chat_content(response)
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
      extract_embeddings(response)
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

    def extract_chat_content(response)
      validate_response!(response)
      response.dig("choices", 0, "message", "content")
    end

    def extract_embeddings(response)
      validate_response!(response)
      response["data"].sort_by { |d| d["index"] }.map { |d| d["embedding"] }
    end

    def validate_response!(response)
      return if response.is_a?(Hash) && !response["error"]

      error_message = response.is_a?(Hash) ? response.dig("error", "message") : "Unknown error"
      raise LlmError, "LLM API error: #{error_message}"
    end

    def with_retry(&block)
      Retriable.retriable(
        on: RETRIABLE_ERRORS,
        tries: MAX_RETRIES + 1,  # retriable counts initial attempt as try 1
        base_interval: RETRY_BASE_INTERVAL,
        max_interval: RETRY_MAX_INTERVAL,
        multiplier: RETRY_MULTIPLIER,
        rand_factor: 0.5,  # Add jitter (0.5-1.5x) like Python implementation
        on_retry: method(:log_retry)
      ) do
        begin
          block.call
        rescue Faraday::ClientError => e
          # Check if it's a rate limit error (429) - should retry
          if rate_limit_error?(e)
            raise Faraday::ServerError, e.message  # Convert to retriable error
          end
          # Other client errors (4xx) should not retry
          raise LlmError, "LLM API error: #{e.message}"
        end
      end
    rescue *RETRIABLE_ERRORS => e
      raise LlmError, "LLM API request failed after #{MAX_RETRIES} retries: #{e.message}"
    end

    def rate_limit_error?(error)
      # Check for 429 status code or rate limit message
      error.message.include?("429") ||
        error.message.downcase.include?("rate limit") ||
        error.message.downcase.include?("too many requests")
    end

    def log_retry(exception, try_number, elapsed_time, next_interval)
      # Log retry attempts for debugging (can be customized or silenced)
      # This matches the Python logging.warning behavior
    end
  end
end
