# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/string/inflections"
require "numo/narray"
require "openai"
require "parallel"
require "json"
require "umappp"

require_relative "broadlistening/version"
require_relative "broadlistening/provider"
require_relative "broadlistening/config"
require_relative "broadlistening/spec_loader"
require_relative "broadlistening/status"
require_relative "broadlistening/planner"
require_relative "broadlistening/comment"
require_relative "broadlistening/argument"
require_relative "broadlistening/csv_loader"
require_relative "broadlistening/compatibility"
require_relative "broadlistening/context"
require_relative "broadlistening/pipeline"

# Services
require_relative "broadlistening/services/llm_client"
require_relative "broadlistening/services/kmeans"
require_relative "broadlistening/services/hierarchical_clustering"

# Steps
require_relative "broadlistening/steps/base_step"
require_relative "broadlistening/steps/extraction"
require_relative "broadlistening/steps/embedding"
require_relative "broadlistening/steps/clustering"
require_relative "broadlistening/steps/initial_labelling"
require_relative "broadlistening/steps/merge_labelling"
require_relative "broadlistening/steps/overview"
require_relative "broadlistening/steps/aggregation"

module Broadlistening
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class LlmError < Error; end
  class ClusteringError < Error; end
end
