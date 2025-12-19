# frozen_string_literal: true

require "spec_helper"
require "dotenv"

# Load environment variables from .env.test.local for integration tests
Dotenv.load(".env.test.local", ".env")

# Allow real HTTP connections for integration tests
WebMock.allow_net_connect!
