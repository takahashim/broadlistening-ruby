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

Results can be visualized as an interactive HTML report using `broadlistening-html`.

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

#### Options

| Option | Description |
|--------|-------------|
| `-f, --force` | Force re-run all steps regardless of previous execution |
| `-o, --only STEP` | Run only the specified step (extraction, embedding, clustering, etc.) |
| `--from STEP` | Resume pipeline from specified step |
| `--input-dir DIR` | Use different input directory for resuming (requires `--from`) |
| `-i, --input FILE` | Input file path (CSV or JSON) - overrides config |
| `-n, --dry-run` | Show what would be executed without actually running |
| `-V, --verbose` | Show detailed output including step parameters and LLM usage |
| `-h, --help` | Show help message |
| `-v, --version` | Show version |

#### Example config.json

```json
{
  "input": "comments.csv",
  "question": "What are the main opinions?",
  "api_key": "sk-...",
  "model": "gpt-4o-mini",
  "cluster_nums": [5, 15]
}
```

#### Input CSV format

```csv
comment-id,comment-body
1,We need environmental measures
2,I hope for better public transportation
```

#### Example

```bash
broadlistening config.json                       # Run full pipeline
broadlistening config.json --dry-run             # Preview without running
broadlistening config.json --from clustering     # Resume from step
broadlistening config.json --input comments.csv  # Override input file
```

### HTML Report Generator

Generate a standalone HTML file from pipeline results for previewing and sharing. The report displays clusters, subclusters, and extracted opinions in an interactive format.

```bash
broadlistening-html outputs/report/hierarchical_result.json            # Generate report
broadlistening-html outputs/report/hierarchical_result.json --help     # Show options
```

## Library Usage

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

### Configuration Options

```ruby
Broadlistening::Pipeline.new(
  api_key: "...",                   # Omit to use env var (OPENAI_API_KEY, GEMINI_API_KEY, etc.)
  model: "gpt-4o-mini",             # LLM model (default: gpt-4o-mini)
  embedding_model: "text-embedding-3-small",  # Embedding model
  cluster_nums: [5, 15],            # Cluster hierarchy levels (default: [5, 15])
  workers: 10,                      # Number of parallel workers
  prompts: { extraction: "...", ... }  # Custom prompts (optional)
)
```

### Using Local LLM (Ollama)

```ruby
config = Broadlistening::Config.new(
  provider: :local,
  model: "llama3",
  embedding_model: "nomic-embed-text",
  local_llm_address: "localhost:11434"
)
```

## Output Format

The pipeline outputs `hierarchical_result.json` containing:
- `arguments` - Extracted opinions with UMAP coordinates and cluster assignments
- `clusters` - Hierarchical cluster structure with labels
- `overview` - LLM-generated summary
- `config` - Pipeline configuration used

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
