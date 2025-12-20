# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/string/inflections"
require "numo/narray"
require "openai"
require "parallel"
require "json"
require "umappp"
require "retriable"

require_relative "broadlistening/version"
require_relative "broadlistening/token_usage"
require_relative "broadlistening/relation"
require_relative "broadlistening/plan_step"
require_relative "broadlistening/cluster_results"
require_relative "broadlistening/cluster_label"
require_relative "broadlistening/cluster_info"
require_relative "broadlistening/completed_job"
require_relative "broadlistening/density_info"
require_relative "broadlistening/pipeline_result"
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
require_relative "broadlistening/context/loader"
require_relative "broadlistening/context/serializer"
require_relative "broadlistening/pipeline"
require_relative "broadlistening/cli"
require_relative "broadlistening/cli/options"
require_relative "broadlistening/cli/parser"
require_relative "broadlistening/cli/validator"
require_relative "broadlistening/html/renderer"
require_relative "broadlistening/html/cli"
require_relative "broadlistening/html/cli/options"

require_relative "broadlistening/json_schemas"
require_relative "broadlistening/llm_client"
require_relative "broadlistening/kmeans"
require_relative "broadlistening/hierarchical_clustering"
require_relative "broadlistening/density_calculator"

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
