# frozen_string_literal: true

module Broadlistening
  class Provider
    PROVIDERS = {
      openai: {
        api_key_env: "OPENAI_API_KEY",
        model: "gpt-4o-mini",
        embedding_model: "text-embedding-3-small"
      },
      azure: {
        api_key_env: "AZURE_OPENAI_API_KEY",
        base_url_env: "AZURE_OPENAI_URI",
        model: "gpt-4o-mini",
        embedding_model: "text-embedding-3-small"
      },
      gemini: {
        api_key_env: "GEMINI_API_KEY",
        base_url: "https://generativelanguage.googleapis.com/v1beta/openai/",
        model: "gemini-2.0-flash",
        embedding_model: "text-embedding-004"
      },
      openrouter: {
        api_key_env: "OPENROUTER_API_KEY",
        base_url: "https://openrouter.ai/api/v1",
        model: "gpt-4o-mini",
        embedding_model: "text-embedding-3-small"
      },
      local: {
        api_key: "not-needed",
        model: "llama3",
        embedding_model: "nomic-embed-text"
      }
    }.freeze

    attr_reader :name

    def self.supported?(name)
      PROVIDERS.key?(name)
    end

    def self.supported_names
      PROVIDERS.keys
    end

    def initialize(name, local_llm_address: nil)
      @name = name
      @local_llm_address = local_llm_address || "localhost:11434"
      @config = PROVIDERS.fetch(name) { raise ConfigurationError, "Unknown provider: #{name}" }
    end

    def api_key
      @config[:api_key] || ENV.fetch(@config[:api_key_env], nil)
    end

    def base_url
      return "http://#{@local_llm_address}/v1" if @name == :local

      @config[:base_url] || (@config[:base_url_env] && ENV.fetch(@config[:base_url_env], nil))
    end

    def default_model
      @config[:model]
    end

    def default_embedding_model
      @config[:embedding_model]
    end

    def requires_api_key?
      @name != :local
    end

    def requires_base_url?
      @name == :azure
    end

    def azure?
      @name == :azure
    end

    def openrouter?
      @name == :openrouter
    end

    def build_openai_client(api_key:, base_url:, azure_api_version: nil)
      if azure?
        OpenAI::Client.new(
          access_token: api_key,
          uri_base: base_url,
          api_type: :azure,
          api_version: azure_api_version
        )
      elsif base_url
        OpenAI::Client.new(access_token: api_key, uri_base: base_url)
      else
        OpenAI::Client.new(access_token: api_key)
      end
    end
  end
end
