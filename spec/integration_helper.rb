# frozen_string_literal: true

require "spec_helper"
require_relative "support/json_extractor"

# Integration tests require API keys as environment variables
# Set them via:
#   - Shell: export OPENAI_API_KEY=sk-...
#   - direnv: add to .envrc
#   - Manual: source .env.test.local

# Allow real HTTP connections for integration tests
WebMock.allow_net_connect!
