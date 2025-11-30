# frozen_string_literal: true

require "spec_helper"

RSpec.describe "JSON Extraction Parsing Compatibility" do
  # Tests for JSON parsing edge cases matching Python's parse_response
  # and parse_extraction_response behavior

  let(:extraction_step) do
    config = Broadlistening::Config.new(
      api_key: "test",
      model: "gpt-4o-mini",
      cluster_nums: [ 2, 5 ]
    )
    context = Broadlistening::Context.new
    Broadlistening::Steps::Extraction.new(config, context)
  end

  describe "parse_extraction_response" do
    describe "structured output format" do
      it "parses extractedOpinionList from dict response" do
        response = '{"extractedOpinionList": ["opinion1", "opinion2"]}'
        result = extraction_step.send(:parse_extraction_response, response)
        expect(result).to eq([ "opinion1", "opinion2" ])
      end

      it "handles empty extractedOpinionList" do
        response = '{"extractedOpinionList": []}'
        result = extraction_step.send(:parse_extraction_response, response)
        expect(result).to eq([])
      end

      it "filters out non-string elements" do
        response = '{"extractedOpinionList": ["valid", 123, null, "also valid"]}'
        result = extraction_step.send(:parse_extraction_response, response)
        expect(result).to eq([ "valid", "also valid" ])
      end

      it "filters out empty strings" do
        response = '{"extractedOpinionList": ["valid", "", "  ", "also valid"]}'
        result = extraction_step.send(:parse_extraction_response, response)
        expect(result).to eq([ "valid", "also valid" ])
      end

      it "handles alternative 'opinions' key" do
        response = '{"opinions": ["opinion1", "opinion2"]}'
        result = extraction_step.send(:parse_extraction_response, response)
        expect(result).to eq([ "opinion1", "opinion2" ])
      end
    end

    describe "direct array response" do
      it "parses JSON array directly" do
        response = '["opinion1", "opinion2", "opinion3"]'
        result = extraction_step.send(:parse_extraction_response, response)
        expect(result).to eq([ "opinion1", "opinion2", "opinion3" ])
      end

      it "strips whitespace from opinions" do
        response = '["  opinion1  ", " opinion2 "]'
        result = extraction_step.send(:parse_extraction_response, response)
        expect(result).to eq([ "opinion1", "opinion2" ])
      end
    end

    describe "single string response" do
      it "wraps single string in array" do
        response = '"single opinion"'
        result = extraction_step.send(:parse_extraction_response, response)
        expect(result).to eq([ "single opinion" ])
      end

      it "strips whitespace from single string" do
        response = '"  single opinion  "'
        result = extraction_step.send(:parse_extraction_response, response)
        expect(result).to eq([ "single opinion" ])
      end

      it "returns empty for empty string" do
        response = '""'
        result = extraction_step.send(:parse_extraction_response, response)
        expect(result).to eq([])
      end
    end
  end

  describe "parse_fallback_response" do
    describe "code block removal" do
      it "removes ```json code blocks" do
        response = "以下は...\n```json\n[\"a\", \"b\"]\n```"
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ "a", "b" ])
      end

      it "removes ``` code blocks without json marker" do
        response = "```\n[\"a\", \"b\"]\n```"
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ "a", "b" ])
      end

      it "handles case-insensitive ```JSON" do
        response = "```JSON\n[\"a\", \"b\"]\n```"
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ "a", "b" ])
      end
    end

    describe "embedded JSON array extraction" do
      it "extracts JSON array from surrounding text" do
        response = "Response was: なんか説明\n[ \"x\", \"y\" ] さらに何か"
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ "x", "y" ])
      end

      it "handles multiline JSON arrays" do
        response = <<~RESPONSE
          以下は要約です。

          [
            "創作文化は…",
            "生成AIは無断で特徴を抽出…",
            "多くのクリエイターは…"
          ]
        RESPONSE
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([
          "創作文化は…",
          "生成AIは無断で特徴を抽出…",
          "多くのクリエイターは…"
        ])
      end
    end

    describe "trailing comma handling" do
      it "fixes trailing comma before ]" do
        response = '["a", "b", ]'
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ "a", "b" ])
      end

      it "fixes trailing comma with whitespace" do
        response = '["a", "b" ,  ]'
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ "a", "b" ])
      end

      it "fixes trailing comma with newline" do
        response = "[\"a\", \"b\",\n]"
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ "a", "b" ])
      end
    end

    describe "edge cases" do
      it "returns empty for completely invalid input" do
        response = "No json here at all"
        result = extraction_step.send(:parse_fallback_response, response)
        # Falls back to line-based parsing
        expect(result).to eq([ "No json here at all" ])
      end

      it "handles empty string" do
        response = ""
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([])
      end

      it "handles whitespace only" do
        response = "   \n   "
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([])
      end

      it "handles nested arrays (takes first level)" do
        response = '[["a", "b"], "c"]'
        result = extraction_step.send(:parse_fallback_response, response)
        # Non-string elements are filtered
        expect(result).to eq([ "c" ])
      end
    end

    describe "unicode support" do
      it "handles Japanese characters" do
        response = '["日本語テスト", "これはテストです"]'
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ "日本語テスト", "これはテストです" ])
      end

      it "handles emoji" do
        response = '["意見 🎉", "テスト ✨"]'
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ "意見 🎉", "テスト ✨" ])
      end
    end

    describe "special characters" do
      it "handles escaped quotes" do
        response = '["He said \\"hello\\"", "Test"]'
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ 'He said "hello"', "Test" ])
      end

      it "handles newlines in strings" do
        response = '["Line1\\nLine2", "Test"]'
        result = extraction_step.send(:parse_fallback_response, response)
        expect(result).to eq([ "Line1\nLine2", "Test" ])
      end
    end
  end

  describe "Python compatibility" do
    # Test cases from Python's doctest
    let(:python_test_cases) do
      [
        {
          input: "以下は...\n```json\n[\"a\", \"b\"]\n```",
          expected: [ "a", "b" ],
          description: "code block with json marker"
        },
        {
          input: "Response was: なんか説明\n[ \"x\", \"y\" ] さらに何か",
          expected: [ "x", "y" ],
          description: "embedded array with surrounding text"
        },
        {
          input: '["a", "b" , ]',
          expected: [ "a", "b" ],
          description: "trailing comma"
        },
        {
          input: '"a"',
          expected: [ "a" ],
          description: "single string"
        }
      ]
    end

    it "matches Python parse_response behavior for all test cases" do
      python_test_cases.each do |test_case|
        result = extraction_step.send(:parse_extraction_response, test_case[:input])
        expect(result).to eq(test_case[:expected]),
          "Failed for #{test_case[:description]}: expected #{test_case[:expected]}, got #{result}"
      end
    end
  end
end
