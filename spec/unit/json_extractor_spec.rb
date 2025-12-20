# frozen_string_literal: true

require "spec_helper"
require_relative "../support/json_extractor"

RSpec.describe JsonExtractor do
  describe ".extract_json" do
    it "handles clean JSON" do
      expect(described_class.extract_json('{"greeting": "hello"}')).to eq('{"greeting": "hello"}')
    end

    it 'handles .{ prefix pattern' do
      input = '.{"greeting": "hello"}'
      result = described_class.extract_json(input)
      expect(JSON.parse(result)).to eq({ "greeting" => "hello" })
    end

    it 'handles .{\n{ double brace pattern' do
      input = ".{\n{\"greeting\": \"hello\"}"
      result = described_class.extract_json(input)
      expect(JSON.parse(result)).to eq({ "greeting" => "hello" })
    end

    it "handles markdown code blocks" do
      input = "```json\n{\"greeting\": \"hello\"}\n```"
      result = described_class.extract_json(input)
      expect(JSON.parse(result)).to eq({ "greeting" => "hello" })
    end

    it "handles nested braces in strings" do
      input = '{"text": "contains { braces }"}'
      result = described_class.extract_json(input)
      expect(JSON.parse(result)).to eq({ "text" => "contains { braces }" })
    end

    it "handles escaped quotes in strings" do
      input = '{"text": "says \"hello\""}'
      result = described_class.extract_json(input)
      expect(JSON.parse(result)).to eq({ "text" => 'says "hello"' })
    end

    it "handles array responses" do
      input = '[{"item": 1}, {"item": 2}]'
      result = described_class.extract_json(input)
      expect(JSON.parse(result)).to eq([ { "item" => 1 }, { "item" => 2 } ])
    end

    it "handles prefix text before array" do
      input = "Here is the result: [{\"item\": 1}]"
      result = described_class.extract_json(input)
      expect(JSON.parse(result)).to eq([ { "item" => 1 } ])
    end

    it "handles complex nested structure" do
      input = ".{\n{\"extractedOpinionList\": [{\"opinion\": \"test\"}]}"
      result = described_class.extract_json(input)
      expect(JSON.parse(result)).to eq({ "extractedOpinionList" => [ { "opinion" => "test" } ] })
    end

    it "raises error when no JSON found" do
      expect { described_class.extract_json("no json here") }.to raise_error(JSON::ParserError)
    end
  end
end
