# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require "csv"

RSpec.describe "Context Serializer Compatibility" do
  # Tests to verify Context::Serializer output formats match Python
  # Python outputs: args.csv, relations.csv, hierarchical_clusters.csv,
  #                 hierarchical_merge_labels.csv, hierarchical_overview.txt

  let(:output_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(output_dir) }

  # Sample data matching Python fixture structure
  let(:comments) do
    [
      Broadlistening::Comment.new(id: "1", body: "Test comment 1", proposal_id: "test"),
      Broadlistening::Comment.new(id: "2", body: "Test comment 2", proposal_id: "test"),
      Broadlistening::Comment.new(id: "3", body: "Test comment 3", proposal_id: "test")
    ]
  end

  let(:arguments) do
    [
      Broadlistening::Argument.new(
        arg_id: "A1_0",
        argument: "Opinion from comment 1",
        comment_id: "1",
        x: 1.5,
        y: 2.5,
        cluster_ids: %w[0 1_0 2_0],
        embedding: Array.new(10) { rand }
      ),
      Broadlistening::Argument.new(
        arg_id: "A1_1",
        argument: "Another opinion from comment 1",
        comment_id: "1",
        x: 1.6,
        y: 2.6,
        cluster_ids: %w[0 1_0 2_1],
        embedding: Array.new(10) { rand }
      ),
      Broadlistening::Argument.new(
        arg_id: "A2_0",
        argument: "Opinion from comment 2",
        comment_id: "2",
        x: 3.5,
        y: 4.5,
        cluster_ids: %w[0 1_1 2_2],
        embedding: Array.new(10) { rand }
      )
    ]
  end

  let(:relations) do
    [
      Broadlistening::Relation.new(arg_id: "A1_0", comment_id: "1"),
      Broadlistening::Relation.new(arg_id: "A1_1", comment_id: "1"),
      Broadlistening::Relation.new(arg_id: "A2_0", comment_id: "2")
    ]
  end

  let(:labels) do
    {
      "1_0" => Broadlistening::ClusterLabel.new(cluster_id: "1_0", level: 1, label: "Category A", description: "Description A"),
      "1_1" => Broadlistening::ClusterLabel.new(cluster_id: "1_1", level: 1, label: "Category B", description: "Description B"),
      "2_0" => Broadlistening::ClusterLabel.new(cluster_id: "2_0", level: 2, label: "Subcategory A1", description: "Sub desc A1"),
      "2_1" => Broadlistening::ClusterLabel.new(cluster_id: "2_1", level: 2, label: "Subcategory A2", description: "Sub desc A2"),
      "2_2" => Broadlistening::ClusterLabel.new(cluster_id: "2_2", level: 2, label: "Subcategory B1", description: "Sub desc B1")
    }
  end

  let(:context) do
    ctx = Broadlistening::Context.new
    ctx.comments = comments
    ctx.arguments = arguments
    ctx.relations = relations
    ctx.labels = labels
    ctx.overview = "Test overview text"
    ctx
  end

  describe "args.csv format" do
    # Python format: arg-id, argument (with hyphens)

    before do
      Broadlistening::Context::Serializer.save_step(context, :extraction, output_dir)
    end

    let(:csv_path) { File.join(output_dir, "args.csv") }
    let(:csv_content) { CSV.read(csv_path, headers: true) }

    it "creates args.csv file" do
      expect(File.exist?(csv_path)).to be true
    end

    it "uses hyphen in column names (Python compatible)" do
      expect(csv_content.headers).to include("arg-id")
      expect(csv_content.headers).not_to include("arg_id")
    end

    it "includes argument column" do
      expect(csv_content.headers).to include("argument")
    end

    it "has correct number of rows" do
      expect(csv_content.size).to eq(arguments.size)
    end

    it "preserves arg_id format (A{comment_id}_{index})" do
      arg_ids = csv_content.map { |row| row["arg-id"] }
      expect(arg_ids).to include("A1_0", "A1_1", "A2_0")
    end

    it "preserves argument text" do
      first_row = csv_content.find { |row| row["arg-id"] == "A1_0" }
      expect(first_row["argument"]).to eq("Opinion from comment 1")
    end
  end

  describe "relations.csv format" do
    # Python format: arg-id, comment-id (with hyphens)

    before do
      Broadlistening::Context::Serializer.save_step(context, :extraction, output_dir)
    end

    let(:csv_path) { File.join(output_dir, "relations.csv") }
    let(:csv_content) { CSV.read(csv_path, headers: true) }

    it "creates relations.csv file" do
      expect(File.exist?(csv_path)).to be true
    end

    it "uses hyphen in column names (Python compatible)" do
      expect(csv_content.headers).to include("arg-id")
      expect(csv_content.headers).to include("comment-id")
    end

    it "has correct number of rows" do
      expect(csv_content.size).to eq(relations.size)
    end

    it "links arg_id to correct comment_id" do
      a1_0_row = csv_content.find { |row| row["arg-id"] == "A1_0" }
      expect(a1_0_row["comment-id"]).to eq("1")
    end
  end

  describe "hierarchical_clusters.csv format" do
    # Python format: arg-id, argument, x, y, cluster-level-1-id, cluster-level-2-id, ...

    before do
      Broadlistening::Context::Serializer.save_step(context, :clustering, output_dir)
    end

    let(:csv_path) { File.join(output_dir, "hierarchical_clusters.csv") }
    let(:csv_content) { CSV.read(csv_path, headers: true) }

    it "creates hierarchical_clusters.csv file" do
      expect(File.exist?(csv_path)).to be true
    end

    it "has base columns with hyphens" do
      expect(csv_content.headers).to include("arg-id")
      expect(csv_content.headers).to include("argument")
      expect(csv_content.headers).to include("x")
      expect(csv_content.headers).to include("y")
    end

    it "has cluster level columns with correct naming" do
      # Python uses cluster-level-N-id format
      expect(csv_content.headers).to include("cluster-level-1-id")
      expect(csv_content.headers).to include("cluster-level-2-id")
    end

    it "has correct number of rows" do
      expect(csv_content.size).to eq(arguments.size)
    end

    it "stores x coordinate as numeric string" do
      first_row = csv_content.first
      expect(first_row["x"]).to match(/^-?\d+\.?\d*$/)
    end

    it "stores y coordinate as numeric string" do
      first_row = csv_content.first
      expect(first_row["y"]).to match(/^-?\d+\.?\d*$/)
    end

    it "stores cluster IDs in level_number format" do
      first_row = csv_content.find { |row| row["arg-id"] == "A1_0" }
      expect(first_row["cluster-level-1-id"]).to eq("1_0")
      expect(first_row["cluster-level-2-id"]).to eq("2_0")
    end
  end

  describe "hierarchical_merge_labels.csv format" do
    # Python format: level, id, label, description, value, parent, density, density_rank, density_rank_percentile

    before do
      Broadlistening::Context::Serializer.save_step(context, :merge_labelling, output_dir)
    end

    let(:csv_path) { File.join(output_dir, "hierarchical_merge_labels.csv") }
    let(:csv_content) { CSV.read(csv_path, headers: true) }

    it "creates hierarchical_merge_labels.csv file" do
      expect(File.exist?(csv_path)).to be true
    end

    it "has all required columns" do
      required_columns = %w[level id label description value parent]
      required_columns.each do |col|
        expect(csv_content.headers).to include(col), "Missing column: #{col}"
      end
    end

    it "has density columns" do
      expect(csv_content.headers).to include("density")
      expect(csv_content.headers).to include("density_rank")
      expect(csv_content.headers).to include("density_rank_percentile")
    end

    it "has correct number of rows (one per label)" do
      expect(csv_content.size).to eq(labels.size)
    end

    it "stores level as integer" do
      level1_row = csv_content.find { |row| row["id"] == "1_0" }
      expect(level1_row["level"]).to eq("1")
    end

    it "stores correct label text" do
      level1_row = csv_content.find { |row| row["id"] == "1_0" }
      expect(level1_row["label"]).to eq("Category A")
    end

    it "stores correct description" do
      level1_row = csv_content.find { |row| row["id"] == "1_0" }
      expect(level1_row["description"]).to eq("Description A")
    end

    it "calculates value as count of arguments in cluster" do
      # 1_0 has A1_0 and A1_1
      level1_0_row = csv_content.find { |row| row["id"] == "1_0" }
      expect(level1_0_row["value"].to_i).to eq(2)
    end

    it "sets parent for level 1 clusters to 0" do
      level1_row = csv_content.find { |row| row["id"] == "1_0" }
      expect(level1_row["parent"]).to eq("0")
    end

    it "sets correct parent for level 2 clusters" do
      # 2_0 is child of 1_0
      level2_row = csv_content.find { |row| row["id"] == "2_0" }
      expect(level2_row["parent"]).to eq("1_0")
    end
  end

  describe "hierarchical_overview.txt format" do
    before do
      Broadlistening::Context::Serializer.save_step(context, :overview, output_dir)
    end

    let(:txt_path) { File.join(output_dir, "hierarchical_overview.txt") }

    it "creates hierarchical_overview.txt file" do
      expect(File.exist?(txt_path)).to be true
    end

    it "contains overview text" do
      content = File.read(txt_path)
      expect(content).to eq("Test overview text")
    end

    it "handles empty overview" do
      context.overview = nil
      Broadlistening::Context::Serializer.save_step(context, :overview, output_dir)
      content = File.read(txt_path)
      expect(content).to eq("")
    end
  end

  describe "Reading Python-generated files" do
    # Test that Ruby can read files generated by Python

    let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }

    describe "args.csv from Python" do
      let(:python_args) { CSV.read(File.join(fixtures_dir, "args.csv"), headers: true) }

      it "has arg-id column with hyphen" do
        expect(python_args.headers).to include("arg-id")
      end

      it "has argument column" do
        expect(python_args.headers).to include("argument")
      end

      it "has valid arg_id format" do
        python_args.each do |row|
          expect(row["arg-id"]).to match(/^A\d+_\d+$/),
            "Invalid arg-id format: #{row['arg-id']}"
        end
      end
    end

    describe "relations.csv from Python" do
      let(:python_relations) { CSV.read(File.join(fixtures_dir, "relations.csv"), headers: true) }

      it "has arg-id column" do
        expect(python_relations.headers).to include("arg-id")
      end

      it "has comment-id column" do
        expect(python_relations.headers).to include("comment-id")
      end
    end

    describe "hierarchical_clusters.csv from Python" do
      let(:python_clusters) { CSV.read(File.join(fixtures_dir, "hierarchical_clusters.csv"), headers: true) }

      it "has base columns" do
        expect(python_clusters.headers).to include("arg-id")
        expect(python_clusters.headers).to include("argument")
        expect(python_clusters.headers).to include("x")
        expect(python_clusters.headers).to include("y")
      end

      it "has cluster level columns" do
        cluster_cols = python_clusters.headers.select { |h| h.start_with?("cluster-level-") }
        expect(cluster_cols).not_to be_empty
      end

      it "has numeric coordinates" do
        python_clusters.each do |row|
          expect { Float(row["x"]) }.not_to raise_error
          expect { Float(row["y"]) }.not_to raise_error
        end
      end
    end

    describe "hierarchical_merge_labels.csv from Python" do
      let(:python_labels) { CSV.read(File.join(fixtures_dir, "hierarchical_merge_labels.csv"), headers: true) }

      it "has required columns" do
        required = %w[level id label description]
        required.each do |col|
          expect(python_labels.headers).to include(col)
        end
      end

      it "has value column" do
        expect(python_labels.headers).to include("value")
      end

      it "has parent column" do
        expect(python_labels.headers).to include("parent")
      end
    end
  end

  describe "Column name consistency" do
    # Ensure Ruby uses the same column naming convention as Python

    it "uses hyphens for multi-word column names (not underscores)" do
      Broadlistening::Context::Serializer.save_step(context, :extraction, output_dir)

      args_csv = CSV.read(File.join(output_dir, "args.csv"), headers: true)
      relations_csv = CSV.read(File.join(output_dir, "relations.csv"), headers: true)

      # Should use hyphens
      expect(args_csv.headers).to include("arg-id")
      expect(relations_csv.headers).to include("arg-id")
      expect(relations_csv.headers).to include("comment-id")

      # Should NOT use underscores for these
      expect(args_csv.headers).not_to include("arg_id")
      expect(relations_csv.headers).not_to include("comment_id")
    end
  end

  describe "Japanese text handling" do
    let(:japanese_context) do
      ctx = Broadlistening::Context.new
      ctx.comments = [
        Broadlistening::Comment.new(id: "1", body: "日本語のコメント", proposal_id: "test")
      ]
      ctx.arguments = [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "日本語の意見です",
          comment_id: "1",
          x: 1.0,
          y: 2.0,
          cluster_ids: %w[0 1_0]
        )
      ]
      ctx.relations = [
        Broadlistening::Relation.new(arg_id: "A1_0", comment_id: "1")
      ]
      ctx.labels = {
        "1_0" => Broadlistening::ClusterLabel.new(
          cluster_id: "1_0",
          level: 1,
          label: "カテゴリA",
          description: "日本語の説明"
        )
      }
      ctx.overview = "日本語の概要テキスト"
      ctx
    end

    it "preserves Japanese text in args.csv" do
      Broadlistening::Context::Serializer.save_step(japanese_context, :extraction, output_dir)
      csv = CSV.read(File.join(output_dir, "args.csv"), headers: true)
      expect(csv.first["argument"]).to eq("日本語の意見です")
    end

    it "preserves Japanese text in merge_labels.csv" do
      Broadlistening::Context::Serializer.save_step(japanese_context, :merge_labelling, output_dir)
      csv = CSV.read(File.join(output_dir, "hierarchical_merge_labels.csv"), headers: true)
      row = csv.first
      expect(row["label"]).to eq("カテゴリA")
      expect(row["description"]).to eq("日本語の説明")
    end

    it "preserves Japanese text in overview.txt" do
      Broadlistening::Context::Serializer.save_step(japanese_context, :overview, output_dir)
      content = File.read(File.join(output_dir, "hierarchical_overview.txt"))
      expect(content).to eq("日本語の概要テキスト")
    end
  end
end
