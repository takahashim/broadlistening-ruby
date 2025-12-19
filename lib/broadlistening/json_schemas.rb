# frozen_string_literal: true

module Broadlistening
  # JSON Schemas for OpenAI Structured Outputs
  # These schemas match Kouchou-AI's Pydantic models
  module JsonSchemas
    # Schema for extraction step (ExtractionResponse in Python)
    EXTRACTION = {
      name: "ExtractionResponse",
      strict: true,
      schema: {
        type: "object",
        properties: {
          extractedOpinionList: {
            type: "array",
            items: { type: "string" },
            description: "抽出した意見のリスト"
          }
        },
        required: [ "extractedOpinionList" ],
        additionalProperties: false
      }
    }.freeze

    # Schema for labelling steps (LabellingFormat in Python)
    LABELLING = {
      name: "LabellingFormat",
      strict: true,
      schema: {
        type: "object",
        properties: {
          label: {
            type: "string",
            description: "クラスタのラベル名"
          },
          description: {
            type: "string",
            description: "クラスタの説明文"
          }
        },
        required: [ "label", "description" ],
        additionalProperties: false
      }
    }.freeze

    # Schema for overview step (OverviewResponse in Python)
    OVERVIEW = {
      name: "OverviewResponse",
      strict: true,
      schema: {
        type: "object",
        properties: {
          summary: {
            type: "string",
            description: "クラスターの全体的な要約"
          }
        },
        required: [ "summary" ],
        additionalProperties: false
      }
    }.freeze
  end
end
