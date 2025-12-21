# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] - 2025-12-21

### Added
- `--input` CLI option to override input file from config
- HTML report generator with CLI (`broadlistening-html` command)
- Subcluster navigation with Erubi templating and XSS protection
- `--from` and `--input-dir` options to resume pipeline from specific step
- `--dry-run` and `--verbose` CLI options (replaced `--skip-interaction`)
- `relations.csv` requirement for extraction step
- Token usage tracking for LLM API calls
- Exponential backoff retry with rate limit support (retriable gem)
- Structured Outputs support for OpenAI API compatibility
- `auto_cluster_nums` feature for automatic cluster number determination
- `limit` setting for comments
- Context class now accepts keyword arguments in initialize
- Integration test infrastructure and LLM integration tests
- Comprehensive Python compatibility tests with fixtures

### Changed
- Refactored Cli class into Options, Parser, and Validator components
- Replaced Hash-based data structures with typed classes (ClusterResults, PlanStep, Relation)
- Refactored DensityCalculator with ClusterPoints Data.define and instance-based design
- Refactored Context with CSV format: extracted Loader/Serializer classes
- Nested Result classes under PipelineResult (Argument, Cluster, Comment)
- Updated default prompts to match Kouchou-AI
- Updated Rice to 4.7.x
- Updated required_ruby_version to >= 3.2.0 for Data classes
- Allow `--from` without `--input-dir`

### Fixed
- JSON parsing error by decoding HTML entities in embedded JSON data
- Step notification timing by separating start and completion events
- LLM array response parsing issues
- OpenRouter response-healing with JsonExtractor helper
- Embedding API compatibility for Gemini
- Bundle hierarchical_specs.json within the gem
- Optional dotenv support for CLI usage
- Show input and output file paths in verbose mode
- Show status.json path in lock error message for easier unlock
- Density calculation and JSON parsing improvements

## [0.7.0] - 2025-11-30

### Added
- Multi-provider support for LLM
  - OpenAI (default)
  - Azure OpenAI
  - Google Gemini
  - OpenRouter
  - Local LLM (Ollama)
- CLI class compatible with Python kouchou-ai `hierarchical_main.py`
  - `broadlistening CONFIG [options]` command
  - `-f, --force` option to force re-run all steps
  - `-o, --only STEP` option to run only specified step
  - `--skip-interaction` option to skip confirmation prompt
  - Auto-generates output directory from config filename (e.g., `config/report.json` → `outputs/report/`)
- Config class now supports `input`, `question`, `name`, and `intro` fields for Python compatibility

### Changed
- Extracted Provider class to separate LLM provider configuration from Config
- Removed Services namespace, moved classes directly to Broadlistening module

### Fixed
- Changed PROVIDERS hash keys from strings to symbols for consistency
- Use single worker in notification tests for deterministic behavior

## [0.1.0] - 2025-11-30

### Added
- Initial implementation of Broadlistening pipeline
- 7-step pipeline: extraction, embedding, clustering, initial_labelling, merge_labelling, overview, aggregation
- Incremental execution support with status tracking
- Output format compatible with Kouchou-AI Python implementation
- ActiveSupport::Notifications for pipeline events
