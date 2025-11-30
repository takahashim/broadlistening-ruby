# Broadlistening

[広聴 AI](https://github.com/digitaldemocracy2030/kouchou-ai)の[Broadlistening パイプライン](https://github.com/digitaldemocracy2030/kouchou-ai/tree/main/server/broadlistening)のRuby実装です。LLMを使用して公開コメントをクラスタリング・分析します。

[in English](./README.md)

## 概要

Broadlistening は、大量のコメントや意見を AI を活用して分析するためのパイプラインです。以下のステップで処理を行います：

1. **Extraction (意見抽出)** - コメントから主要な意見を LLM で抽出
2. **Embedding (ベクトル化)** - 抽出した意見をベクトル化
3. **Clustering (クラスタリング)** - UMAP + KMeans + 階層的クラスタリング
4. **Initial Labelling (初期ラベリング)** - 各クラスタに LLM でラベル付け
5. **Merge Labelling (ラベル統合)** - 階層的にラベルを統合
6. **Overview (概要生成)** - 全体の概要を LLM で生成
7. **Aggregation (JSON 組み立て)** - 結果を JSON 形式で出力

## インストール

Gemfile に追加：

```ruby
gem 'broadlistening'
```

依存関係のインストール：

```bash
bundle install
```

## 使い方

### コマンドラインインターフェース

インストール後、`broadlistening` コマンドが使用できます：

```bash
broadlistening config.json [options]
```

**オプション:**
- `-f, --force` - 以前の実行結果に関係なく、すべてのステップを強制的に再実行
- `-o, --only STEP` - 指定したステップのみを実行（extraction, embedding, clustering など）
- `--skip-interaction` - 確認プロンプトをスキップして即座に実行
- `-h, --help` - ヘルプメッセージを表示
- `-v, --version` - バージョンを表示

**config.json の例:**

```json
{
  "input": "comments.csv",
  "question": "主な意見は何ですか？",
  "api_key": "sk-...",
  "model": "gpt-4o-mini",
  "cluster_nums": [5, 15]
}
```

**入力 CSV フォーマット:**

```csv
comment-id,comment-body
1,環境問題への対策が必要です
2,公共交通機関の充実を希望します
```

**実行例:**

```bash
# パイプライン全体を実行
broadlistening config.json

# すべてのステップを強制的に再実行
broadlistening config.json --force

# extraction ステップのみを実行
broadlistening config.json --only extraction

# 確認プロンプトなしで実行
broadlistening config.json --skip-interaction
```

### Ruby API

```ruby
require 'broadlistening'

# コメントデータを準備
comments = [
  { id: "1", body: "環境問題への対策が必要です", proposal_id: "123" },
  { id: "2", body: "公共交通機関の充実を希望します", proposal_id: "123" },
  # ...
]

# パイプラインを実行
pipeline = Broadlistening::Pipeline.new(
  api_key: ENV['OPENAI_API_KEY'],
  model: "gpt-4o-mini",
  cluster_nums: [5, 15]
)
result = pipeline.run(comments)

# 結果を取得
puts result[:overview]
puts result[:clusters]
```

### Rails での使用例

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
    result = pipeline.run(comments)

    proposal.create_analysis_result!(
      result_data: result,
      comment_count: comments.size
    )
  end
end
```

### 設定オプション

```ruby
Broadlistening::Pipeline.new(
  api_key: "your-api-key",          # OpenAI API キー（必須）
  model: "gpt-4o-mini",             # LLM モデル（デフォルト: gpt-4o-mini）
  embedding_model: "text-embedding-3-small",  # 埋め込みモデル
  cluster_nums: [5, 15],            # クラスタ階層の数（デフォルト: [5, 15]）
  workers: 10,                      # 並列処理のワーカー数
  prompts: {                        # カスタムプロンプト（オプション）
    extraction: "...",
    initial_labelling: "...",
    merge_labelling: "...",
    overview: "..."
  }
)
```

### ローカル LLM の使用

GPU を搭載したマシンでローカル LLM を使用したい場合は、以下の手順に従ってください：

1. Ollama をインストールして起動します
2. 必要なモデルをダウンロードします：
   ```sh
   ollama pull llama3
   ollama pull nomic-embed-text
   ```
3. Ruby で `provider: :local` を指定して使用します：
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

**注意**:

- ローカル LLM の使用には十分な GPU メモリが必要です（8GB 以上推奨）
- 初回起動時にはモデルのダウンロードに時間がかかる場合があります

## 出力形式

パイプラインの結果は以下の構造を持つ Hash です：

```ruby
{
  arguments: [
    {
      arg_id: "A1_0",
      argument: "環境問題への対策が必要",
      x: 0.5,           # UMAP X座標
      y: 0.3,           # UMAP Y座標
      cluster_ids: ["0", "1_0", "2_3"]  # 所属クラスタID
    },
    # ...
  ],
  clusters: [
    {
      level: 0,
      id: "0",
      label: "全体",
      description: "",
      count: 100,
      parent: nil
    },
    {
      level: 1,
      id: "1_0",
      label: "環境・エネルギー",
      description: "環境問題やエネルギー政策に関する意見",
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
  overview: "分析の概要テキスト...",
  config: { model: "gpt-4o-mini", ... }
}
```

## 依存関係

- Ruby >= 3.1.0
- activesupport >= 7.0
- numo-narray ~> 0.9
- ruby-openai ~> 7.0
- parallel ~> 1.20
- rice ~> 4.6.0
- umappp ~> 0.2

### umappp のインストール

[umappp](https://rubygems.org/gems/umappp) は C++ ネイティブ拡張を含むため、インストール時に C++ コンパイラが必要です：

```bash
# macOS
CXX=clang++ gem install umappp

# Linux
gem install umappp
```

**注意**: Rice 4.7.x との互換性問題があるため、Rice 4.6.x を使用してください。

## 開発

```bash
# セットアップ
bin/setup

# テスト実行
bundle exec rspec

# コンソール
bin/console
```

## ライセンス

AGPL 3.0
