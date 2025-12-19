# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Parent Calculation Compatibility" do
  # Tests to verify parent calculation matches Python behavior
  # Python computes parent in hierarchical_merge_labelling._build_parent_child_mapping
  # Ruby computes parent in Steps::Aggregation#find_parent_cluster

  let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }

  describe "Python output parent structure" do
    let(:python_result) do
      JSON.parse(File.read(File.join(fixtures_dir, "hierarchical_result.json")))
    end

    let(:python_labels_csv) do
      CSV.read(File.join(fixtures_dir, "hierarchical_merge_labels.csv"), headers: true)
    end

    describe "root cluster" do
      it "has empty parent" do
        root = python_result["clusters"].find { |c| c["level"] == 0 }
        expect(root["parent"]).to eq(""),
          "Root cluster should have empty parent, got '#{root['parent']}'"
      end
    end

    describe "level 1 clusters" do
      it "all have parent '0'" do
        level_1_clusters = python_result["clusters"].select { |c| c["level"] == 1 }

        level_1_clusters.each do |cluster|
          expect(cluster["parent"]).to eq("0"),
            "Level 1 cluster #{cluster['id']} should have parent '0', got '#{cluster['parent']}'"
        end
      end
    end

    describe "level 2 clusters" do
      it "all have valid level 1 cluster as parent" do
        level_1_ids = python_result["clusters"]
          .select { |c| c["level"] == 1 }
          .map { |c| c["id"] }

        level_2_clusters = python_result["clusters"].select { |c| c["level"] == 2 }

        level_2_clusters.each do |cluster|
          expect(level_1_ids).to include(cluster["parent"]),
            "Level 2 cluster #{cluster['id']} has invalid parent '#{cluster['parent']}'"
        end
      end
    end

    describe "CSV and JSON consistency" do
      it "parent values in CSV match JSON" do
        python_labels_csv.each do |row|
          cluster_id = row["id"]
          csv_parent = row["parent"]

          json_cluster = python_result["clusters"].find { |c| c["id"] == cluster_id }
          next unless json_cluster

          expect(json_cluster["parent"]).to eq(csv_parent),
            "Cluster #{cluster_id}: CSV parent '#{csv_parent}' != JSON parent '#{json_cluster['parent']}'"
        end
      end
    end
  end

  describe "Ruby parent calculation" do
    let(:python_result) do
      JSON.parse(File.read(File.join(fixtures_dir, "hierarchical_result.json")))
    end

    let(:python_clusters_csv) do
      CSV.read(File.join(fixtures_dir, "hierarchical_clusters.csv"), headers: true)
    end

    let(:python_labels_csv) do
      CSV.read(File.join(fixtures_dir, "hierarchical_merge_labels.csv"), headers: true)
    end

    let(:python_relations_csv) do
      CSV.read(File.join(fixtures_dir, "relations.csv"), headers: true)
    end

    let(:config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 5, 15 ]
      )
    end

    let(:comments) do
      comment_ids = python_relations_csv.map { |r| r["comment-id"].to_s }.uniq
      comment_ids.map do |id|
        Broadlistening::Comment.new(
          id: id,
          body: "Test comment #{id}",
          proposal_id: "test"
        )
      end
    end

    let(:arguments) do
      python_clusters_csv.map do |row|
        cluster_columns = python_clusters_csv.headers.select { |h| h.start_with?("cluster-level-") }
        cluster_ids = [ "0" ] + cluster_columns.map { |col| row[col] }

        relation = python_relations_csv.find { |r| r["arg-id"] == row["arg-id"] }
        comment_id = relation ? relation["comment-id"] : row["arg-id"].match(/A(\d+)_/)[1]

        Broadlistening::Argument.new(
          arg_id: row["arg-id"],
          argument: row["argument"],
          comment_id: comment_id,
          x: row["x"].to_f,
          y: row["y"].to_f,
          cluster_ids: cluster_ids
        )
      end
    end

    let(:labels) do
      python_labels_csv.each_with_object({}) do |row, hash|
        hash[row["id"]] = Broadlistening::ClusterLabel.new(
          cluster_id: row["id"],
          level: row["level"].to_i,
          label: row["label"],
          description: row["description"]
        )
      end
    end

    let(:cluster_results) do
      cluster_columns = python_clusters_csv.headers.select { |h| h.start_with?("cluster-level-") }

      hash = cluster_columns.each_with_index.each_with_object({}) do |(col, idx), results|
        level = idx + 1
        results[level] = python_clusters_csv.map do |row|
          row[col].split("_").last.to_i
        end
      end
      Broadlistening::ClusterResults.from_h(hash)
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = comments
      ctx.arguments = arguments
      ctx.labels = labels
      ctx.cluster_results = cluster_results
      ctx.overview = "Test overview"
      ctx
    end

    let(:aggregation_step) { Broadlistening::Steps::Aggregation.new(config, context) }

    let(:ruby_result) do
      aggregation_step.execute
      context.result.to_h
    end

    describe "parent matching Python" do
      it "produces same parent for root cluster" do
        ruby_root = ruby_result[:clusters].find { |c| c[:level] == 0 }
        python_root = python_result["clusters"].find { |c| c["level"] == 0 }

        expect(ruby_root[:parent]).to eq(python_root["parent"]),
          "Root parent: Ruby='#{ruby_root[:parent]}' Python='#{python_root['parent']}'"
      end

      it "produces same parent for level 1 clusters" do
        ruby_level_1 = ruby_result[:clusters].select { |c| c[:level] == 1 }

        ruby_level_1.each do |ruby_cluster|
          python_cluster = python_result["clusters"].find { |c| c["id"] == ruby_cluster[:id] }
          next unless python_cluster

          expect(ruby_cluster[:parent]).to eq(python_cluster["parent"]),
            "Cluster #{ruby_cluster[:id]}: Ruby parent='#{ruby_cluster[:parent]}' Python parent='#{python_cluster['parent']}'"
        end
      end

      it "produces same parent for level 2 clusters" do
        ruby_level_2 = ruby_result[:clusters].select { |c| c[:level] == 2 }

        ruby_level_2.each do |ruby_cluster|
          python_cluster = python_result["clusters"].find { |c| c["id"] == ruby_cluster[:id] }
          next unless python_cluster

          expect(ruby_cluster[:parent]).to eq(python_cluster["parent"]),
            "Cluster #{ruby_cluster[:id]}: Ruby parent='#{ruby_cluster[:parent]}' Python parent='#{python_cluster['parent']}'"
        end
      end
    end

    describe "parent calculation correctness" do
      it "verifies parent is accessible via cluster_ids chain" do
        ruby_level_2 = ruby_result[:clusters].select { |c| c[:level] == 2 }

        ruby_level_2.each do |cluster|
          # Find an argument in this cluster
          arg = arguments.find { |a| a.cluster_ids.include?(cluster[:id]) }
          next unless arg

          # Verify parent is in cluster_ids chain
          parent_id = cluster[:parent]
          expect(arg.cluster_ids).to include(parent_id),
            "Cluster #{cluster[:id]}'s parent #{parent_id} not in argument #{arg.arg_id}'s cluster_ids: #{arg.cluster_ids}"
        end
      end
    end
  end

  describe "Edge cases" do
    describe "3-level hierarchy" do
      let(:config) do
        Broadlistening::Config.new(
          api_key: "test",
          model: "gpt-4o-mini",
          cluster_nums: [ 2, 4, 8 ]
        )
      end

      let(:context) do
        ctx = Broadlistening::Context.new
        ctx.comments = 16.times.map do |i|
          Broadlistening::Comment.new(id: i.to_s, body: "Comment #{i}", proposal_id: "test")
        end
        ctx.arguments = 16.times.map do |i|
          Broadlistening::Argument.new(
            arg_id: "A#{i}_0",
            argument: "Opinion #{i}",
            comment_id: i.to_s,
            embedding: Array.new(10) { rand }
          )
        end
        ctx
      end

      before do
        # Run clustering to get cluster_ids
        clustering = Broadlistening::Steps::Clustering.new(config, context)
        clustering.execute

        # Create mock labels
        context.labels = {}
        context.arguments.each do |arg|
          arg.cluster_ids[1..].each do |cid|
            next if context.labels[cid]

            level = cid.split("_").first.to_i
            context.labels[cid] = Broadlistening::ClusterLabel.new(
              cluster_id: cid,
              level: level,
              label: "Cluster #{cid}",
              description: "Description for #{cid}"
            )
          end
        end

        context.overview = "Test overview"
      end

      let(:aggregation_step) { Broadlistening::Steps::Aggregation.new(config, context) }

      let(:result) do
        aggregation_step.execute
        context.result.to_h
      end

      it "level 3 clusters have level 2 parent" do
        level_2_ids = result[:clusters].select { |c| c[:level] == 2 }.map { |c| c[:id] }
        level_3_clusters = result[:clusters].select { |c| c[:level] == 3 }

        level_3_clusters.each do |cluster|
          expect(level_2_ids).to include(cluster[:parent]),
            "Level 3 cluster #{cluster[:id]} has parent #{cluster[:parent]} which is not a level 2 cluster"
        end
      end

      it "parent chain forms valid path to root" do
        cluster_map = result[:clusters].each_with_object({}) { |c, h| h[c[:id]] = c }

        result[:clusters].each do |cluster|
          next if cluster[:level] == 0

          # Walk up the parent chain
          current = cluster
          visited = Set.new

          while current[:parent] && !current[:parent].empty?
            expect(visited).not_to include(current[:id]),
              "Circular reference detected at #{current[:id]}"
            visited.add(current[:id])

            parent = cluster_map[current[:parent]]
            expect(parent).not_to be_nil,
              "Cluster #{current[:id]} references non-existent parent #{current[:parent]}"
            expect(parent[:level]).to eq(current[:level] - 1),
              "Parent #{parent[:id]} at level #{parent[:level]} should be at level #{current[:level] - 1}"

            current = parent
          end

          # Should end at root
          expect(current[:level]).to eq(0),
            "Parent chain for #{cluster[:id]} did not reach root, stopped at #{current[:id]}"
        end
      end
    end

    describe "unbalanced hierarchy" do
      # Some level 1 clusters might have more children than others
      let(:config) do
        Broadlistening::Config.new(
          api_key: "test",
          model: "gpt-4o-mini",
          cluster_nums: [ 2, 6 ]
        )
      end

      let(:context) do
        ctx = Broadlistening::Context.new
        ctx.comments = 12.times.map do |i|
          Broadlistening::Comment.new(id: i.to_s, body: "Comment #{i}", proposal_id: "test")
        end
        ctx.arguments = 12.times.map do |i|
          Broadlistening::Argument.new(
            arg_id: "A#{i}_0",
            argument: "Opinion #{i}",
            comment_id: i.to_s,
            embedding: Array.new(10) { rand }
          )
        end
        ctx
      end

      before do
        clustering = Broadlistening::Steps::Clustering.new(config, context)
        clustering.execute

        context.labels = {}
        context.arguments.each do |arg|
          arg.cluster_ids[1..].each do |cid|
            next if context.labels[cid]

            level = cid.split("_").first.to_i
            context.labels[cid] = Broadlistening::ClusterLabel.new(
              cluster_id: cid,
              level: level,
              label: "Cluster #{cid}",
              description: "Description for #{cid}"
            )
          end
        end

        context.overview = "Test overview"
      end

      it "all level 2 clusters have valid level 1 parent" do
        aggregation = Broadlistening::Steps::Aggregation.new(config, context)
        aggregation.execute
        result = context.result.to_h

        level_1_ids = result[:clusters].select { |c| c[:level] == 1 }.map { |c| c[:id] }
        level_2_clusters = result[:clusters].select { |c| c[:level] == 2 }

        level_2_clusters.each do |cluster|
          expect(level_1_ids).to include(cluster[:parent]),
            "Level 2 cluster #{cluster[:id]} has invalid parent #{cluster[:parent]}"
        end
      end

      it "child values sum to parent value" do
        aggregation = Broadlistening::Steps::Aggregation.new(config, context)
        aggregation.execute
        result = context.result.to_h

        level_1_clusters = result[:clusters].select { |c| c[:level] == 1 }
        level_2_clusters = result[:clusters].select { |c| c[:level] == 2 }

        level_1_clusters.each do |parent|
          children = level_2_clusters.select { |c| c[:parent] == parent[:id] }
          children_sum = children.sum { |c| c[:value] }

          expect(children_sum).to eq(parent[:value]),
            "Children of #{parent[:id]} sum to #{children_sum}, expected #{parent[:value]}"
        end
      end
    end
  end
end
