# Broadlistening

A Ruby implementation of the [Kouchou-AI](https://github.com/digitaldemocracy2030/kouchou-ai) [Broadlistening pipeline](https://github.com/digitaldemocracy2030/kouchou-ai/tree/main/server/broadlistening). Clusters and analyzes public comments using LLM.

[in Japanese](./README.ja.md)

## Overview

Broadlistening is a pipeline for analyzing large volumes of comments and opinions using AI. It processes data through the following steps:

1. **Extraction** - Extract key opinions from comments using LLM
2. **Embedding** - Vectorize extracted opinions
3. **Clustering** - UMAP + KMeans + hierarchical clustering
4. **Initial Labelling** - Label each cluster using LLM
5. **Merge Labelling** - Hierarchically integrate labels
6. **Overview** - Generate overall summary using LLM
7. **Aggregation** - Output results in JSON format

## Installation

Add to your Gemfile:

```ruby
gem 'broadlistening'
```

Then run:

```bash
bundle install
```

## Usage

### Command Line Interface

After installation, you can use the `broadlistening` command:

```bash
broadlistening config.json [options]
```

**Options:**
- `-f, --force` - Force re-run all steps regardless of previous execution
- `-o, --only STEP` - Run only the specified step (extraction, embedding, clustering, etc.)
- `--skip-interaction` - Skip the interactive confirmation prompt
- `-h, --help` - Show help message
- `-v, --version` - Show version

**Example config.json:**

```json
{
  "input": "comments.csv",
  "question": "What are the main opinions?",
  "api_key": "sk-...",
  "model": "gpt-4o-mini",
  "cluster_nums": [5, 15]
}
```

**Input CSV format:**

```csv
comment-id,comment-body
1,We need environmental measures
2,I hope for better public transportation
```

**Example:**

```bash
# Run the full pipeline
broadlistening config.json

# Force re-run all steps
broadlistening config.json --force

# Run only the extraction step
broadlistening config.json --only extraction

# Run without confirmation prompt
broadlistening config.json --skip-interaction
```

### Ruby API

```ruby
require 'broadlistening'

# Prepare comment data
comments = [
  { id: "1", body: "We need environmental measures", proposal_id: "123" },
  { id: "2", body: "I hope for better public transportation", proposal_id: "123" },
  # ...
]

# Run the pipeline
pipeline = Broadlistening::Pipeline.new(
  api_key: ENV['OPENAI_API_KEY'],
  model: "gpt-4o-mini",
  cluster_nums: [5, 15]
)
result = pipeline.run(comments, output_dir: "./output")

# Get results
puts result[:overview]
puts result[:clusters]
```

### Rails Example

```ruby
# app/jobs/analysis_job.rb
class AnalysisJob < ApplicationJob
  queue_as :analysis

  def perform(proposal_id)
    proposal = Proposal.find(proposal_id)
    comments = proposal.comments.map do |c|
      { id: c.id, body: c.body, proposal_id: c.proposal_id }
    end

    pipeline = Broadlistening::Pipeline.new(
      api_key: ENV['OPENAI_API_KEY'],
      model: "gpt-4o-mini",
      cluster_nums: [5, 15]
    )
    result = pipeline.run(comments, output_dir: "./output")

    proposal.create_analysis_result!(
      result_data: result,
      comment_count: comments.size
    )
  end
end
```

### Configuration Options

```ruby
Broadlistening::Pipeline.new(
  api_key: "your-api-key",          # OpenAI API key (required)
  model: "gpt-4o-mini",             # LLM model (default: gpt-4o-mini)
  embedding_model: "text-embedding-3-small",  # Embedding model
  cluster_nums: [5, 15],            # Cluster hierarchy levels (default: [5, 15])
  workers: 10,                      # Number of parallel workers
  prompts: {                        # Custom prompts (optional)
    extraction: "...",
    initial_labelling: "...",
    merge_labelling: "...",
    overview: "..."
  }
)
```

### Using Local LLM

If you want to use a local LLM on a machine with GPU, follow these steps:

1. Install and start Ollama
2. Download the required models:
   ```sh
   ollama pull llama3
   ollama pull nomic-embed-text
   ```
3. Use `provider: :local` in Ruby:
   ```ruby
   config = Broadlistening::Config.new(
     provider: :local,
     model: "llama3",
     embedding_model: "nomic-embed-text",
     local_llm_address: "localhost:11434",
     cluster_nums: [5, 15]
   )
   pipeline = Broadlistening::Pipeline.new(config)
   result = pipeline.run(comments, output_dir: "./output")
   ```

**Note**:

- Using local LLM requires sufficient GPU memory (8GB or more recommended)
- Model downloads may take time on first startup

## Output Format

The pipeline result is a Hash with the following structure:

```ruby
{
  arguments: [
    {
      arg_id: "A1_0",
      argument: "Environmental measures are needed",
      x: 0.5,           # UMAP X coordinate
      y: 0.3,           # UMAP Y coordinate
      cluster_ids: ["0", "1_0", "2_3"]  # Cluster IDs
    },
    # ...
  ],
  clusters: [
    {
      level: 0,
      id: "0",
      label: "All",
      description: "",
      count: 100,
      parent: nil
    },
    {
      level: 1,
      id: "1_0",
      label: "Environment & Energy",
      description: "Opinions on environmental issues and energy policy",
      count: 25,
      parent: "0"
    },
    # ...
  ],
  relations: [
    { arg_id: "A1_0", comment_id: "1", proposal_id: "123" },
    # ...
  ],
  comment_count: 50,
  argument_count: 100,
  overview: "Analysis summary text...",
  config: { model: "gpt-4o-mini", ... }
}
```

## Dependencies

- Ruby >= 3.1.0
- activesupport >= 7.0
- numo-narray ~> 0.9
- ruby-openai ~> 7.0
- parallel ~> 1.20
- rice ~> 4.6.0
- umappp ~> 0.2

### Installing umappp

umappp includes C++ native extensions and requires a C++ compiler:

```bash
# macOS
CXX=clang++ gem install umappp

# Linux
gem install umappp
```

**Note**: Use Rice 4.6.x due to compatibility issues with Rice 4.7.x.

## Development

```bash
# Setup
bin/setup

# Run tests
bundle exec rspec

# Console
bin/console
```

## License

AGPL 3.0
