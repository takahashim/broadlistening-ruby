# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Clustering Compatibility" do
  # Load Python-generated fixtures
  let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }

  let(:python_embeddings) do
    # Load embeddings from pickle and convert to JSON for Ruby
    embeddings_json_path = File.join(fixtures_dir, "embeddings.json")
    unless File.exist?(embeddings_json_path)
      skip "embeddings.json not found. Run: python scripts/convert_embeddings_to_json.py"
    end
    JSON.parse(File.read(embeddings_json_path))
  end

  let(:python_clusters) do
    csv_path = File.join(fixtures_dir, "hierarchical_clusters.csv")
    CSV.read(csv_path, headers: true)
  end

  let(:python_result) do
    JSON.parse(File.read(File.join(fixtures_dir, "hierarchical_result.json")))
  end

  let(:cluster_nums) { [ 5, 15 ] }

  describe "Python output structure validation" do
    it "has expected number of arguments" do
      expect(python_result["arguments"].size).to eq(686)
    end

    it "has expected number of clusters" do
      # 1 root + 5 level-1 + 15 level-2 = 21
      expect(python_result["clusters"].size).to eq(21)
    end

    it "has correct hierarchy levels" do
      levels = python_result["clusters"].map { |c| c["level"] }.uniq.sort
      expect(levels).to eq([ 0, 1, 2 ])
    end

    it "has valid cluster ID format" do
      python_result["clusters"].each do |cluster|
        if cluster["level"] == 0
          expect(cluster["id"]).to eq("0")
        else
          expect(cluster["id"]).to match(/^\d+_\d+$/)
        end
      end
    end

    it "has valid parent references" do
      cluster_ids = python_result["clusters"].map { |c| c["id"] }

      python_result["clusters"].each do |cluster|
        next if cluster["level"] == 0

        parent_id = cluster["parent"]
        expect(cluster_ids).to include(parent_id),
          "Cluster #{cluster['id']} references non-existent parent #{parent_id}"
      end
    end

    it "has consistent cluster value counts" do
      # Root cluster should have value equal to total arguments
      root = python_result["clusters"].find { |c| c["level"] == 0 }
      expect(root["value"]).to eq(python_result["arguments"].size)

      # Level 1 clusters should sum to total
      level_1_sum = python_result["clusters"]
        .select { |c| c["level"] == 1 }
        .sum { |c| c["value"] }
      expect(level_1_sum).to eq(root["value"])
    end
  end

  describe "Arguments cluster_ids structure" do
    it "all arguments have cluster_ids starting with root '0'" do
      python_result["arguments"].each do |arg|
        expect(arg["cluster_ids"].first).to eq("0"),
          "Argument #{arg['arg_id']} does not start with root cluster"
      end
    end

    it "all arguments have cluster_ids with correct level count" do
      expected_levels = cluster_nums.size + 1 # +1 for root
      python_result["arguments"].each do |arg|
        expect(arg["cluster_ids"].size).to eq(expected_levels),
          "Argument #{arg['arg_id']} has #{arg['cluster_ids'].size} levels, expected #{expected_levels}"
      end
    end

    it "all cluster_ids in arguments reference existing clusters" do
      cluster_ids = python_result["clusters"].map { |c| c["id"] }

      python_result["arguments"].each do |arg|
        arg["cluster_ids"].each do |cid|
          expect(cluster_ids).to include(cid),
            "Argument #{arg['arg_id']} references non-existent cluster #{cid}"
        end
      end
    end
  end

  describe "Coordinate range validation" do
    it "has x coordinates in reasonable UMAP range" do
      x_values = python_result["arguments"].map { |a| a["x"] }
      expect(x_values.min).to be > -20
      expect(x_values.max).to be < 20
    end

    it "has y coordinates in reasonable UMAP range" do
      y_values = python_result["arguments"].map { |a| a["y"] }
      expect(y_values.min).to be > -20
      expect(y_values.max).to be < 20
    end

    it "has coordinates with reasonable variance" do
      x_values = python_result["arguments"].map { |a| a["x"] }
      y_values = python_result["arguments"].map { |a| a["y"] }

      x_variance = x_values.map { |x| (x - x_values.sum / x_values.size) ** 2 }.sum / x_values.size
      y_variance = y_values.map { |y| (y - y_values.sum / y_values.size) ** 2 }.sum / y_values.size

      # Variance should be non-trivial (not all same point)
      expect(x_variance).to be > 0.1
      expect(y_variance).to be > 0.1
    end
  end

  describe "Cluster hierarchy consistency" do
    it "level 1 clusters all have root as parent" do
      level_1 = python_result["clusters"].select { |c| c["level"] == 1 }
      level_1.each do |cluster|
        expect(cluster["parent"]).to eq("0"),
          "Level 1 cluster #{cluster['id']} has parent #{cluster['parent']}, expected '0'"
      end
    end

    it "level 2 clusters all have level 1 clusters as parent" do
      level_1_ids = python_result["clusters"]
        .select { |c| c["level"] == 1 }
        .map { |c| c["id"] }

      level_2 = python_result["clusters"].select { |c| c["level"] == 2 }
      level_2.each do |cluster|
        expect(level_1_ids).to include(cluster["parent"]),
          "Level 2 cluster #{cluster['id']} has invalid parent #{cluster['parent']}"
      end
    end

    it "child cluster values sum to parent value" do
      level_1 = python_result["clusters"].select { |c| c["level"] == 1 }
      level_2 = python_result["clusters"].select { |c| c["level"] == 2 }

      level_1.each do |parent|
        children = level_2.select { |c| c["parent"] == parent["id"] }
        children_sum = children.sum { |c| c["value"] }
        expect(children_sum).to eq(parent["value"]),
          "Children of #{parent['id']} sum to #{children_sum}, expected #{parent['value']}"
      end
    end
  end

  describe "JSON Schema validation" do
    it "validates against JSON Schema" do
      errors = Broadlistening::Compatibility.validate_with_schema(python_result)
      expect(errors).to be_empty, "Schema validation errors: #{errors.map { |e| e[:message] }.join(', ')}"
    end
  end
end
