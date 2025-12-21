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

結果は `broadlistening-html` でインタラクティブな HTML レポートとして可視化できます。

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

#### オプション

| オプション | 説明 |
|------------|------|
| `-f, --force` | 以前の実行結果に関係なく、すべてのステップを強制的に再実行 |
| `-o, --only STEP` | 指定したステップのみを実行（extraction, embedding, clustering など） |
| `--from STEP` | 指定したステップからパイプラインを再開 |
| `--input-dir DIR` | 再開時に別の入力ディレクトリを使用（`--from` と併用） |
| `-i, --input FILE` | 入力ファイルのパス（CSV または JSON）- config を上書き |
| `-n, --dry-run` | 実際に実行せずに何が実行されるかを表示 |
| `-V, --verbose` | ステップのパラメータや LLM 使用量などの詳細を表示 |
| `-h, --help` | ヘルプメッセージを表示 |
| `-v, --version` | バージョンを表示 |

#### config.json の例

```json
{
  "input": "comments.csv",
  "question": "主な意見は何ですか？",
  "api_key": "sk-...",
  "model": "gpt-4o-mini",
  "cluster_nums": [5, 15]
}
```

#### 入力 CSV フォーマット

```csv
comment-id,comment-body
1,環境問題への対策が必要です
2,公共交通機関の充実を希望します
```

#### 実行例

```bash
broadlistening config.json                        # パイプライン全体を実行
broadlistening config.json --dry-run              # 実行内容をプレビュー
broadlistening config.json --from clustering      # 指定ステップから再開
broadlistening config.json --input commments.csv  # 入力ファイルを上書き
```

### HTML レポートジェネレーター

パイプラインの結果から単体の HTML ファイルを生成します。プレビューや共有に便利です。クラスタ、サブクラスタ、抽出された意見をインタラクティブに表示します。

```bash
broadlistening-html outputs/report/hierarchical_result.json            # レポート生成
broadlistening-html outputs/report/hierarchical_result.json --help     # オプション表示
```

## ライブラリとしての使い方

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

### 設定オプション

```ruby
Broadlistening::Pipeline.new(
  api_key: "...",                   # 省略時は環境変数を使用（OPENAI_API_KEY, GEMINI_API_KEY など）
  model: "gpt-4o-mini",             # LLM モデル（デフォルト: gpt-4o-mini）
  embedding_model: "text-embedding-3-small",  # 埋め込みモデル
  cluster_nums: [5, 15],            # クラスタ階層の数（デフォルト: [5, 15]）
  workers: 10,                      # 並列処理のワーカー数
  prompts: { extraction: "...", ... }  # カスタムプロンプト（オプション）
)
```

### ローカル LLM の使用 (Ollama)

```ruby
config = Broadlistening::Config.new(
  provider: :local,
  model: "llama3",
  embedding_model: "nomic-embed-text",
  local_llm_address: "localhost:11434"
)
```

## 出力形式

パイプラインは `hierarchical_result.json` を出力します：
- `arguments` - UMAP 座標とクラスタ割り当てを含む抽出された意見
- `clusters` - ラベル付きの階層的クラスタ構造
- `overview` - LLM が生成した概要
- `config` - 使用したパイプライン設定

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

Copyright (C) 2025 Masayoshi Takahashi

This repository is licensed under the GNU Affero General Public License v3.0.
Unless otherwise noted, all files in this repository are covered by this license.
See the LICENSE file for details.
