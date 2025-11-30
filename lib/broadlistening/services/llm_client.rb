# frozen_string_literal: true

module Broadlistening
  module Services
    class LlmClient
      MAX_RETRIES = 3
      RETRY_DELAY = 1

      def initialize(config)
        @config = config
        @client = build_client
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

      def build_client
        case @config.provider
        when "openai"
          OpenAI::Client.new(access_token: @config.api_key)
        when "azure"
          OpenAI::Client.new(
            access_token: @config.api_key,
            uri_base: @config.api_base_url,
            api_type: :azure,
            api_version: @config.azure_api_version
          )
        when "gemini", "openrouter", "local"
          OpenAI::Client.new(
            access_token: @config.api_key,
            uri_base: @config.api_base_url
          )
        else
          raise ConfigurationError, "Unknown provider: #{@config.provider}"
        end
      end

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

      def with_retry
        retries = 0
        begin
          yield
        rescue Faraday::ClientError => e
          raise LlmError, "LLM API error: #{e.message}"
        rescue Faraday::ServerError, Faraday::ConnectionFailed, Faraday::TimeoutError,
               Net::OpenTimeout, Errno::ECONNRESET => e
          retries += 1
          raise LlmError, "LLM API request failed after #{MAX_RETRIES} retries: #{e.message}" if retries > MAX_RETRIES

          sleep(RETRY_DELAY * retries)
          retry
        end
      end
    end
  end
end
