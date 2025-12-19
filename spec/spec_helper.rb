# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
end

require "webmock/rspec"
require "broadlistening"

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    WebMock.reset!
  end

  # Integration test configuration
  config.define_derived_metadata(file_path: %r{spec/integration}) do |metadata|
    metadata[:integration] = true
  end

  # Skip integration tests unless RUN_INTEGRATION environment variable is set
  config.filter_run_excluding integration: true unless ENV["RUN_INTEGRATION"]
end
