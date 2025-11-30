# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Broadlistening is a Ruby gem that implements the broadlistening pipeline for clustering and analyzing public comments using LLM. It is a Ruby port of the Kouchou-AI (広聴AI) Python implementation, designed for use in Rails applications and other Ruby environments.

## Development Commands

```bash
# Setup
bin/setup

# Run all tests
bundle exec rspec

# Run a single test file
bundle exec rspec spec/pipeline_spec.rb

# Run compatibility tests only
bundle exec rspec spec/compatibility/

# Run a specific test by line number
bundle exec rspec spec/pipeline_spec.rb:42

# Linting
bundle exec rubocop

# Auto-fix lint issues
bundle exec rubocop -A

# Interactive console
bin/console
```

### Compatibility Tasks

```bash
# Validate Python output structure against schema
bundle exec rake compatibility:validate_python

# Compare Python and Ruby outputs
bundle exec rake "compatibility:compare[python_output.json,ruby_output.json]"
```

## Architecture

### Pipeline Flow

The pipeline processes comments through 7 sequential steps:

1. **Extraction** - Extract opinions from comments using LLM
2. **Embedding** - Vectorize extracted opinions using OpenAI embeddings
3. **Clustering** - UMAP dimensionality reduction + KMeans + hierarchical clustering
4. **Initial Labelling** - LLM-based labeling for each cluster
5. **Merge Labelling** - Hierarchical label integration
6. **Overview** - LLM-generated summary of all clusters
7. **Aggregation** - Assemble final JSON output

### Key Components

- **Pipeline** (`lib/broadlistening/pipeline.rb`) - Orchestrates step execution, handles incremental execution
- **Context** (`lib/broadlistening/context.rb`) - Manages all data flowing through pipeline, supports load/save for incremental execution
- **Config** (`lib/broadlistening/config.rb`) - Configuration management, compatible with Python config.json format
- **SpecLoader** (`lib/broadlistening/spec_loader.rb`) - Loads step specifications from Python's hierarchical_specs.json
- **Planner** (`lib/broadlistening/planner.rb`) - Determines which steps need to run based on dependencies
- **Status** (`lib/broadlistening/status.rb`) - Tracks execution status and locking

### Services

- `LlmClient` - OpenAI API wrapper for chat completions
- `KMeans` - K-means clustering implementation using Numo::NArray
- `HierarchicalClustering` - Builds hierarchical cluster structure

### Steps

All steps inherit from `Steps::BaseStep` and implement `execute` method:
- Steps read from and write to Context
- Each step has an output file defined in Context::OUTPUT_FILES
- Dependencies between steps are defined in hierarchical_specs.json

## Technology Stack

- **Ruby**: >= 3.1.0
- **Numerical Computing**: Numo::NArray
- **Dimensionality Reduction**: umappp (C++ native extension)
- **LLM**: ruby-openai
- **Parallelization**: parallel gem
- **Schema Validation**: json_schemer
- **Code Style**: rubocop-rails-omakase, rubocop-rspec

## Kouchou-AI Compatibility

This gem produces output compatible with Kouchou-AI's hierarchical_result.json format:
- Schema defined in `schema/hierarchical_result.json`
- Use `Compatibility.validate_with_schema(output)` to validate
- Step specs loaded from Python's `server/broadlistening/pipeline/hierarchical_specs.json`

### Output Format

Final result includes: arguments, clusters, comments, propertyMap, translations, overview, config

## Native Extension Notes

The umappp gem requires a C++ compiler:
```bash
# macOS
CXX=clang++ gem install umappp

# Use Rice 4.6.x (compatibility issues with 4.7.x)
```
