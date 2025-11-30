# frozen_string_literal: true

RSpec.describe Broadlistening do
  it "has a version number" do
    expect(Broadlistening::VERSION).not_to be_nil
  end

  it "defines error classes" do
    expect(Broadlistening::Error).to be < StandardError
    expect(Broadlistening::ConfigurationError).to be < Broadlistening::Error
    expect(Broadlistening::LlmError).to be < Broadlistening::Error
    expect(Broadlistening::ClusteringError).to be < Broadlistening::Error
  end
end
