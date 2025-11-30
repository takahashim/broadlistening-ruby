# frozen_string_literal: true

RSpec.describe Broadlistening::Services::LlmClient do
  let(:api_key) { "test-api-key" }
  let(:config) do
    Broadlistening::Config.new(
      api_key: api_key,
      model: "gpt-4o-mini",
      embedding_model: "text-embedding-3-small"
    )
  end
  let(:client) { described_class.new(config) }

  describe "#chat" do
    let(:system_prompt) { "You are a helpful assistant." }
    let(:user_message) { "Hello, how are you?" }

    context "when the API returns a successful response" do
      before do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .with(
            body: hash_including(
              "model" => "gpt-4o-mini",
              "messages" => [
                { "role" => "system", "content" => system_prompt },
                { "role" => "user", "content" => user_message }
              ]
            ),
            headers: { "Authorization" => "Bearer #{api_key}" }
          )
          .to_return(
            status: 200,
            body: {
              "choices" => [
                {
                  "message" => {
                    "content" => "I'm doing well, thank you!"
                  }
                }
              ]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns the message content" do
        result = client.chat(system: system_prompt, user: user_message)
        expect(result).to eq("I'm doing well, thank you!")
      end
    end

    context "with json_mode enabled" do
      before do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .with(
            body: hash_including(
              "response_format" => { "type" => "json_object" }
            )
          )
          .to_return(
            status: 200,
            body: {
              "choices" => [
                {
                  "message" => {
                    "content" => '{"result": "success"}'
                  }
                }
              ]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "includes response_format in the request" do
        result = client.chat(system: system_prompt, user: user_message, json_mode: true)
        expect(result).to eq('{"result": "success"}')
      end
    end

    context "when the API returns a client error (4xx)" do
      before do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_raise(Faraday::BadRequestError.new("Invalid request", { status: 400 }))
      end

      it "raises an LlmError without retrying" do
        expect { client.chat(system: system_prompt, user: user_message) }
          .to raise_error(Broadlistening::LlmError, /Invalid request/)
      end
    end

    context "when the API request fails with network error" do
      before do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_raise(Faraday::ConnectionFailed.new("Connection refused"))
      end

      it "retries and raises LlmError after max retries" do
        expect { client.chat(system: system_prompt, user: user_message) }
          .to raise_error(Broadlistening::LlmError, /failed after 3 retries/)
      end
    end

    context "when the API request succeeds after retry" do
      before do
        call_count = 0
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return do |_request|
            call_count += 1
            if call_count < 2
              raise Faraday::ConnectionFailed, "Connection refused"
            else
              {
                status: 200,
                body: {
                  "choices" => [
                    { "message" => { "content" => "Success after retry" } }
                  ]
                }.to_json,
                headers: { "Content-Type" => "application/json" }
              }
            end
          end
      end

      it "returns the result after successful retry" do
        result = client.chat(system: system_prompt, user: user_message)
        expect(result).to eq("Success after retry")
      end
    end
  end

  describe "#embed" do
    context "with a single text" do
      before do
        stub_request(:post, "https://api.openai.com/v1/embeddings")
          .with(
            body: hash_including(
              "model" => "text-embedding-3-small",
              "input" => [ "Hello world" ]
            ),
            headers: { "Authorization" => "Bearer #{api_key}" }
          )
          .to_return(
            status: 200,
            body: {
              "data" => [
                { "index" => 0, "embedding" => [ 0.1, 0.2, 0.3 ] }
              ]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns embeddings for the text" do
        result = client.embed("Hello world")
        expect(result).to eq([ [ 0.1, 0.2, 0.3 ] ])
      end
    end

    context "with multiple texts" do
      before do
        stub_request(:post, "https://api.openai.com/v1/embeddings")
          .with(
            body: hash_including(
              "model" => "text-embedding-3-small",
              "input" => [ "Hello", "World" ]
            )
          )
          .to_return(
            status: 200,
            body: {
              "data" => [
                { "index" => 1, "embedding" => [ 0.4, 0.5, 0.6 ] },
                { "index" => 0, "embedding" => [ 0.1, 0.2, 0.3 ] }
              ]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns embeddings sorted by index" do
        result = client.embed([ "Hello", "World" ])
        expect(result).to eq([ [ 0.1, 0.2, 0.3 ], [ 0.4, 0.5, 0.6 ] ])
      end
    end

    context "when the API returns a client error" do
      before do
        stub_request(:post, "https://api.openai.com/v1/embeddings")
          .to_raise(Faraday::BadRequestError.new("Model not found", { status: 400 }))
      end

      it "raises an LlmError without retrying" do
        expect { client.embed("test") }
          .to raise_error(Broadlistening::LlmError, /Model not found/)
      end
    end

    context "with empty input" do
      before do
        stub_request(:post, "https://api.openai.com/v1/embeddings")
          .with(body: hash_including("input" => []))
          .to_return(
            status: 200,
            body: { "data" => [] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns empty array for empty input" do
        result = client.embed([])
        expect(result).to eq([])
      end
    end
  end

  describe "retry mechanism" do
    let(:system_prompt) { "Test" }
    let(:user_message) { "Test" }

    context "with timeout errors" do
      before do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_raise(Net::OpenTimeout.new("execution expired"))
      end

      it "retries on timeout" do
        expect { client.chat(system: system_prompt, user: user_message) }
          .to raise_error(Broadlistening::LlmError, /failed after 3 retries/)
      end
    end

    context "with connection reset" do
      before do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_raise(Errno::ECONNRESET.new("Connection reset by peer"))
      end

      it "retries on connection reset" do
        expect { client.chat(system: system_prompt, user: user_message) }
          .to raise_error(Broadlistening::LlmError, /failed after 3 retries/)
      end
    end
  end

  describe "provider support" do
    let(:system_prompt) { "You are a helpful assistant." }
    let(:user_message) { "Hello" }

    context "with Azure provider" do
      let(:config) do
        Broadlistening::Config.new(
          api_key: "azure-api-key",
          provider: "azure",
          api_base_url: "https://my-resource.openai.azure.com",
          azure_api_version: "2024-02-15-preview"
        )
      end

      before do
        stub_request(:post, "https://my-resource.openai.azure.com/chat/completions?api-version=2024-02-15-preview")
          .to_return(
            status: 200,
            body: { "choices" => [ { "message" => { "content" => "Azure response" } } ] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "sends requests to Azure endpoint" do
        result = client.chat(system: system_prompt, user: user_message)
        expect(result).to eq("Azure response")
      end
    end

    context "with Gemini provider" do
      let(:config) do
        Broadlistening::Config.new(
          api_key: "gemini-api-key",
          provider: "gemini",
          model: "gemini-2.0-flash"
        )
      end

      before do
        stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
          .to_return(
            status: 200,
            body: { "choices" => [ { "message" => { "content" => "Gemini response" } } ] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "sends requests to Gemini endpoint" do
        result = client.chat(system: system_prompt, user: user_message)
        expect(result).to eq("Gemini response")
      end
    end

    context "with OpenRouter provider" do
      let(:config) do
        Broadlistening::Config.new(
          api_key: "openrouter-api-key",
          provider: "openrouter",
          model: "anthropic/claude-3-haiku"
        )
      end

      before do
        stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
          .to_return(
            status: 200,
            body: { "choices" => [ { "message" => { "content" => "OpenRouter response" } } ] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "sends requests to OpenRouter endpoint" do
        result = client.chat(system: system_prompt, user: user_message)
        expect(result).to eq("OpenRouter response")
      end
    end

    context "with local provider" do
      let(:config) do
        Broadlistening::Config.new(
          provider: "local",
          local_llm_address: "localhost:11434",
          model: "llama3"
        )
      end

      before do
        stub_request(:post, "http://localhost:11434/v1/chat/completions")
          .to_return(
            status: 200,
            body: { "choices" => [ { "message" => { "content" => "Local LLM response" } } ] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "sends requests to local LLM endpoint" do
        result = client.chat(system: system_prompt, user: user_message)
        expect(result).to eq("Local LLM response")
      end
    end
  end
end
