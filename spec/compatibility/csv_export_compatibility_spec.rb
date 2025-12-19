# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe "CSV Export Compatibility" do
  # Tests to verify CSV export format matches Python behavior
  # Python: hierarchical_aggregation.add_original_comments
  # Ruby: Steps::Aggregation#export_csv

  # Python CSV column format (from actual output):
  # comment-id,original-comment,arg_id,argument,category_id,category,source,url,attribute_*

  describe "Column structure" do
    let(:config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 2, 5 ],
        is_pubcom: true
      )
    end

    let(:output_dir) { Dir.mktmpdir }

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.output_dir = output_dir

      ctx.comments = [
        Broadlistening::Comment.new(
          id: "1",
          body: "Test comment 1",
          proposal_id: "test",
          source: "survey",
          url: "https://example.com/1",
          attributes: { "gender" => "male", "age" => "30" }
        ),
        Broadlistening::Comment.new(
          id: "2",
          body: "Test comment 2",
          proposal_id: "test",
          source: "email",
          url: "https://example.com/2",
          attributes: { "gender" => "female", "age" => "25" }
        )
      ]

      ctx.arguments = [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "Opinion 1",
          comment_id: "1",
          x: 1.5,
          y: 2.5,
          cluster_ids: [ "0", "1_0", "2_0" ],
          attributes: { "gender" => "male", "age" => "30" }
        ),
        Broadlistening::Argument.new(
          arg_id: "A2_0",
          argument: "Opinion 2",
          comment_id: "2",
          x: 3.5,
          y: 4.5,
          cluster_ids: [ "0", "1_1", "2_1" ],
          attributes: { "gender" => "female", "age" => "25" }
        )
      ]

      ctx.labels = {
        "1_0" => Broadlistening::ClusterLabel.new(
          cluster_id: "1_0",
          level: 1,
          label: "Category A",
          description: "Description A"
        ),
        "1_1" => Broadlistening::ClusterLabel.new(
          cluster_id: "1_1",
          level: 1,
          label: "Category B",
          description: "Description B"
        ),
        "2_0" => Broadlistening::ClusterLabel.new(
          cluster_id: "2_0",
          level: 2,
          label: "Subcategory A1",
          description: "Description A1"
        ),
        "2_1" => Broadlistening::ClusterLabel.new(
          cluster_id: "2_1",
          level: 2,
          label: "Subcategory B1",
          description: "Description B1"
        )
      }

      ctx.cluster_results = Broadlistening::ClusterResults.new
      ctx.cluster_results.set(1, 0, 0)
      ctx.cluster_results.set(1, 1, 1)
      ctx.cluster_results.set(2, 0, 0)
      ctx.cluster_results.set(2, 1, 1)

      ctx.overview = "Test overview"
      ctx
    end

    after { FileUtils.rm_rf(output_dir) }

    let(:aggregation_step) { Broadlistening::Steps::Aggregation.new(config, context) }

    let(:csv_path) { File.join(output_dir, "final_result_with_comments.csv") }

    let(:csv_content) do
      aggregation_step.execute
      CSV.read(csv_path, headers: true)
    end

    describe "required base columns (Python format)" do
      # Python uses hyphen for these columns
      it "has comment-id column (hyphen, not underscore)" do
        expect(csv_content.headers).to include("comment-id")
      end

      it "has original-comment column (hyphen, not underscore)" do
        expect(csv_content.headers).to include("original-comment")
      end

      it "has arg_id column" do
        expect(csv_content.headers).to include("arg_id")
      end

      it "has argument column" do
        expect(csv_content.headers).to include("argument")
      end

      it "has category_id column" do
        expect(csv_content.headers).to include("category_id")
      end

      it "has category column" do
        expect(csv_content.headers).to include("category")
      end
    end

    describe "optional columns from source data" do
      it "includes source column when comments have source" do
        expect(csv_content.headers).to include("source")
      end

      it "includes url column when comments have url" do
        expect(csv_content.headers).to include("url")
      end

      it "includes x column when arguments have x coordinate" do
        expect(csv_content.headers).to include("x")
      end

      it "includes y column when arguments have y coordinate" do
        expect(csv_content.headers).to include("y")
      end
    end

    describe "column order (Python format)" do
      it "has correct base column order" do
        headers = csv_content.headers
        base_cols = headers.reject { |h| h.start_with?("attribute_") }

        # Python order: comment-id, original-comment, arg_id, argument, category_id, category, source, url, x, y
        expected_order = %w[comment-id original-comment arg_id argument category_id category]

        # Check first 6 columns match exactly
        expect(base_cols[0, 6]).to eq(expected_order)
      end
    end

    describe "attribute columns" do
      it "includes attribute columns with prefix" do
        attr_cols = csv_content.headers.select { |h| h.start_with?("attribute_") }
        expect(attr_cols).to include("attribute_gender")
        expect(attr_cols).to include("attribute_age")
      end

      it "sorts attribute columns alphabetically" do
        attr_cols = csv_content.headers.select { |h| h.start_with?("attribute_") }
        expect(attr_cols).to eq(attr_cols.sort)
      end
    end
  end

  describe "Value formatting" do
    let(:config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 2, 5 ],
        is_pubcom: true
      )
    end

    let(:output_dir) { Dir.mktmpdir }

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.output_dir = output_dir

      ctx.comments = [
        Broadlistening::Comment.new(
          id: "1",
          body: "日本語のコメント with special chars: <>&\"'",
          proposal_id: "test",
          source: "survey",
          url: "https://example.com/test?id=1"
        )
      ]

      ctx.arguments = [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "日本語の意見",
          comment_id: "1",
          x: 1.23456789,
          y: -2.98765432,
          cluster_ids: [ "0", "1_0", "2_0" ]
        )
      ]

      ctx.labels = {
        "1_0" => Broadlistening::ClusterLabel.new(
          cluster_id: "1_0",
          level: 1,
          label: "カテゴリA",
          description: "説明A"
        ),
        "2_0" => Broadlistening::ClusterLabel.new(
          cluster_id: "2_0",
          level: 2,
          label: "サブカテゴリA1",
          description: "説明A1"
        )
      }

      ctx.cluster_results = Broadlistening::ClusterResults.new
      ctx.cluster_results.set(1, 0, 0)
      ctx.cluster_results.set(2, 0, 0)

      ctx.overview = "Test overview"
      ctx
    end

    after { FileUtils.rm_rf(output_dir) }

    let(:aggregation_step) { Broadlistening::Steps::Aggregation.new(config, context) }

    let(:csv_path) { File.join(output_dir, "final_result_with_comments.csv") }

    let(:csv_content) do
      aggregation_step.execute
      CSV.read(csv_path, headers: true)
    end

    it "preserves Japanese characters in comments" do
      row = csv_content.first
      expect(row["original-comment"]).to include("日本語のコメント")
    end

    it "preserves Japanese characters in arguments" do
      row = csv_content.first
      expect(row["argument"]).to eq("日本語の意見")
    end

    it "preserves Japanese characters in categories" do
      row = csv_content.first
      expect(row["category"]).to eq("カテゴリA")
    end

    it "properly escapes special characters" do
      row = csv_content.first
      expect(row["original-comment"]).to include("<>&\"'")
    end

    it "formats coordinates as floats" do
      row = csv_content.first
      expect(row["x"]).to match(/^\-?\d+\.\d+$/)
      expect(row["y"]).to match(/^\-?\d+\.\d+$/)
    end

    it "preserves URL with query parameters" do
      row = csv_content.first
      expect(row["url"]).to eq("https://example.com/test?id=1")
    end
  end

  describe "Missing data handling" do
    let(:config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 2, 5 ],
        is_pubcom: true
      )
    end

    let(:output_dir) { Dir.mktmpdir }

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.output_dir = output_dir

      # Comment without source/url
      ctx.comments = [
        Broadlistening::Comment.new(
          id: "1",
          body: "Comment without source/url",
          proposal_id: "test"
        )
      ]

      ctx.arguments = [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "Opinion 1",
          comment_id: "1",
          x: 1.0,
          y: 2.0,
          cluster_ids: [ "0", "1_0", "2_0" ]
        )
      ]

      ctx.labels = {
        "1_0" => Broadlistening::ClusterLabel.new(
          cluster_id: "1_0",
          level: 1,
          label: "Category",
          description: "Description"
        ),
        "2_0" => Broadlistening::ClusterLabel.new(
          cluster_id: "2_0",
          level: 2,
          label: "Subcategory",
          description: "Description"
        )
      }

      ctx.cluster_results = Broadlistening::ClusterResults.new
      ctx.cluster_results.set(1, 0, 0)
      ctx.cluster_results.set(2, 0, 0)

      ctx.overview = "Test overview"
      ctx
    end

    after { FileUtils.rm_rf(output_dir) }

    let(:aggregation_step) { Broadlistening::Steps::Aggregation.new(config, context) }

    let(:csv_path) { File.join(output_dir, "final_result_with_comments.csv") }

    it "handles missing source gracefully" do
      aggregation_step.execute
      csv_content = CSV.read(csv_path, headers: true)

      if csv_content.headers.include?("source")
        row = csv_content.first
        # Should be nil or empty string
        expect(row["source"]).to be_nil.or eq("")
      end
    end

    it "handles missing url gracefully" do
      aggregation_step.execute
      csv_content = CSV.read(csv_path, headers: true)

      if csv_content.headers.include?("url")
        row = csv_content.first
        # Should be nil or empty string
        expect(row["url"]).to be_nil.or eq("")
      end
    end

    it "handles argument without matching comment" do
      # Add argument with non-existent comment_id
      context.arguments << Broadlistening::Argument.new(
        arg_id: "A999_0",
        argument: "Orphan opinion",
        comment_id: "999",
        x: 5.0,
        y: 6.0,
        cluster_ids: [ "0", "1_0", "2_0" ]
      )

      aggregation_step.execute
      csv_content = CSV.read(csv_path, headers: true)

      orphan_row = csv_content.find { |r| r["arg_id"] == "A999_0" }
      expect(orphan_row).not_to be_nil
      expect(orphan_row["original-comment"]).to eq("").or be_nil
    end
  end

  describe "Round-trip compatibility" do
    let(:config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 2, 5 ],
        is_pubcom: true
      )
    end

    let(:output_dir) { Dir.mktmpdir }

    after { FileUtils.rm_rf(output_dir) }

    it "produces CSV that can be read back correctly" do
      ctx = Broadlistening::Context.new
      ctx.output_dir = output_dir

      ctx.comments = [
        Broadlistening::Comment.new(
          id: "1",
          body: "Original comment",
          proposal_id: "test",
          attributes: { "attr1" => "value1" }
        )
      ]

      ctx.arguments = [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "Test argument",
          comment_id: "1",
          x: 1.0,
          y: 2.0,
          cluster_ids: [ "0", "1_0", "2_0" ],
          attributes: { "attr1" => "value1" }
        )
      ]

      ctx.labels = {
        "1_0" => Broadlistening::ClusterLabel.new(
          cluster_id: "1_0",
          level: 1,
          label: "Cat",
          description: "Desc"
        ),
        "2_0" => Broadlistening::ClusterLabel.new(
          cluster_id: "2_0",
          level: 2,
          label: "SubCat",
          description: "SubDesc"
        )
      }

      ctx.cluster_results = Broadlistening::ClusterResults.new
      ctx.cluster_results.set(1, 0, 0)
      ctx.cluster_results.set(2, 0, 0)
      ctx.overview = "Test"

      aggregation = Broadlistening::Steps::Aggregation.new(config, ctx)
      aggregation.execute

      csv_path = File.join(output_dir, "final_result_with_comments.csv")
      csv_content = CSV.read(csv_path, headers: true)

      expect(csv_content.size).to eq(1)
      row = csv_content.first
      expect(row["arg_id"]).to eq("A1_0")
      expect(row["argument"]).to eq("Test argument")
      expect(row["category_id"]).to eq("1_0")
      expect(row["category"]).to eq("Cat")
    end
  end
end
