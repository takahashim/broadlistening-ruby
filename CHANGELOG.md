# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.0] - 2024-11-30

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

## [0.1.0] - 2024-11-30

### Added
- Initial implementation of Broadlistening pipeline
- 7-step pipeline: extraction, embedding, clustering, initial_labelling, merge_labelling, overview, aggregation
- Incremental execution support with status tracking
- Output format compatible with Kouchou-AI Python implementation
- ActiveSupport::Notifications for pipeline events
