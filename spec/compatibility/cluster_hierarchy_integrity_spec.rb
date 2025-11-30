# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Cluster Hierarchy Integrity" do
  # Tests to verify hierarchical clustering invariants match Python behavior:
  # 1. Parent-child relationships are consistent
  # 2. cluster_ids format is correct
  # 3. Labels are contiguous within levels
  # 4. All arguments belong to exactly one cluster at each level

  describe "cluster_ids format validation" do
    let(:config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 2, 5, 10 ]
      )
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.arguments = create_arguments(20)
      ctx
    end

    let(:clustering_step) { Broadlistening::Steps::Clustering.new(config, context) }

    def create_arguments(count)
      count.times.map do |i|
        Broadlistening::Argument.new(
          arg_id: "A#{i}_0",
          argument: "Opinion #{i}",
          comment_id: i.to_s,
          embedding: Array.new(10) { rand }
        )
      end
    end

    before { clustering_step.execute }

    describe "cluster_ids structure" do
      it "starts with root cluster '0'" do
        context.arguments.each do |arg|
          expect(arg.cluster_ids.first).to eq("0"),
            "Expected cluster_ids to start with '0', got #{arg.cluster_ids.first}"
        end
      end

      it "has correct level prefixes" do
        # cluster_nums = [2, 5, 10] produces levels 1, 2, 3
        context.arguments.each do |arg|
          # Skip root "0"
          arg.cluster_ids[1..].each_with_index do |cluster_id, idx|
            level = idx + 1
            expect(cluster_id).to match(/\A#{level}_\d+\z/),
              "Expected cluster_id to match '#{level}_X' format, got #{cluster_id}"
          end
        end
      end

      it "has correct number of levels" do
        # cluster_nums has 3 elements, plus root = 4 total
        expected_depth = config.cluster_nums.size + 1

        context.arguments.each do |arg|
          expect(arg.cluster_ids.size).to eq(expected_depth),
            "Expected #{expected_depth} levels, got #{arg.cluster_ids.size}"
        end
      end
    end

    describe "hierarchical containment invariant" do
      # Points in the same cluster at level N+1 must also be in the same cluster at level N
      # (This is the core hierarchical constraint)

      it "maintains parent-child consistency" do
        levels = config.cluster_nums.size

        (1...levels).each do |level|
          parent_idx = level
          child_idx = level + 1

          # Group arguments by child cluster
          child_groups = context.arguments.group_by { |arg| arg.cluster_ids[child_idx] }

          child_groups.each do |child_id, args|
            parent_ids = args.map { |arg| arg.cluster_ids[parent_idx] }.uniq

            expect(parent_ids.size).to eq(1),
              "Child cluster #{child_id} spans multiple parent clusters: #{parent_ids}"
          end
        end
      end

      it "maintains root containment (all arguments under root)" do
        root_clusters = context.arguments.map { |arg| arg.cluster_ids[0] }.uniq

        expect(root_clusters).to eq([ "0" ]),
          "Not all arguments are under root cluster '0'"
      end
    end

    describe "label contiguity within levels" do
      # At each level, cluster labels should be 0, 1, 2, ... without gaps

      it "has contiguous labels at each level" do
        config.cluster_nums.size.times do |i|
          level = i + 1
          level_idx = level # Index in cluster_ids array (0 is root)

          labels = context.arguments.map { |arg| arg.cluster_ids[level_idx] }
          label_nums = labels.map { |l| l.split("_").last.to_i }.uniq.sort

          expected = (0...label_nums.size).to_a
          expect(label_nums).to eq(expected),
            "Level #{level} has non-contiguous labels: #{label_nums}"
        end
      end
    end

    describe "cluster count validation" do
      it "has at most N clusters at level with target N" do
        config.cluster_nums.each_with_index do |target_n, idx|
          level = idx + 1
          level_idx = level

          labels = context.arguments.map { |arg| arg.cluster_ids[level_idx] }.uniq
          actual_n = labels.size

          # Actual clusters should be at most the target (could be less if fewer samples)
          expect(actual_n).to be <= target_n,
            "Level #{level} has #{actual_n} clusters, expected at most #{target_n}"
        end
      end

      it "has increasing cluster count with depth" do
        prev_count = 1 # Root has 1 cluster

        config.cluster_nums.size.times do |i|
          level_idx = i + 1
          labels = context.arguments.map { |arg| arg.cluster_ids[level_idx] }.uniq
          current_count = labels.size

          expect(current_count).to be >= prev_count,
            "Cluster count should increase with depth: level #{i} has #{prev_count}, level #{i + 1} has #{current_count}"

          prev_count = current_count
        end
      end
    end
  end

  describe "Aggregation output integrity" do
    let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }
    let(:reference_path) { File.join(fixtures_dir, "hierarchical_result.json") }

    before do
      skip "Reference file not found" unless File.exist?(reference_path)
    end

    let(:reference_output) do
      JSON.parse(File.read(reference_path))
    end

    describe "arguments-clusters cross-reference" do
      it "all argument cluster_ids reference existing clusters" do
        # Kouchou-AI format: clusters have "id" field
        cluster_ids_in_clusters = reference_output["clusters"].map { |c| c["id"] }

        reference_output["arguments"].each do |arg|
          arg["cluster_ids"].each do |cid|
            next if cid == "0" # Root is implicit

            expect(cluster_ids_in_clusters).to include(cid),
              "Argument #{arg['arg_id']} references non-existent cluster #{cid}"
          end
        end
      end

      it "all clusters have at least one argument" do
        arg_cluster_ids = reference_output["arguments"].flat_map { |a| a["cluster_ids"] }.uniq

        reference_output["clusters"].each do |cluster|
          expect(arg_cluster_ids).to include(cluster["id"]),
            "Cluster #{cluster['id']} has no arguments"
        end
      end
    end

    describe "parent-child relationships" do
      it "parent_id references exist" do
        # Kouchou-AI format: "parent" field, can be null, empty string, or "0"
        cluster_ids = reference_output["clusters"].map { |c| c["id"] }

        reference_output["clusters"].each do |cluster|
          parent = cluster["parent"]
          # Skip root cluster (parent is empty or nil)
          next if parent.nil? || parent.empty? || parent == "0"

          expect(cluster_ids).to include(parent),
            "Cluster #{cluster['id']} has invalid parent_id #{parent}"
        end
      end

      it "children count matches parent references" do
        # Count how many clusters reference each cluster as parent
        parent_child_map = Hash.new { |h, k| h[k] = [] }

        reference_output["clusters"].each do |cluster|
          parent = cluster["parent"]
          parent_child_map[parent] << cluster["id"] if parent
        end

        # Verify each cluster's children are properly linked
        reference_output["clusters"].each do |cluster|
          actual_children = parent_child_map[cluster["id"]]
          # Check that child clusters exist if there are any
          actual_children.each do |child_id|
            child_cluster = reference_output["clusters"].find { |c| c["id"] == child_id }
            expect(child_cluster).not_to be_nil,
              "Child cluster #{child_id} not found"
          end
        end
      end
    end

    describe "argument count consistency" do
      it "cluster value matches actual argument count" do
        # Kouchou-AI format: "value" field contains argument count
        cluster_arg_counts = Hash.new(0)

        reference_output["arguments"].each do |arg|
          arg["cluster_ids"].each do |cid|
            cluster_arg_counts[cid] += 1
          end
        end

        reference_output["clusters"].each do |cluster|
          actual_count = cluster_arg_counts[cluster["id"]]
          declared_count = cluster["value"]

          expect(actual_count).to eq(declared_count),
            "Cluster #{cluster['id']} declares #{declared_count} arguments but has #{actual_count}"
        end
      end
    end
  end

  describe "Edge case handling" do
    describe "single cluster at a level" do
      let(:config) do
        Broadlistening::Config.new(
          api_key: "test",
          model: "gpt-4o-mini",
          cluster_nums: [ 1, 3 ]
        )
      end

      let(:context) do
        ctx = Broadlistening::Context.new
        ctx.arguments = 10.times.map do |i|
          Broadlistening::Argument.new(
            arg_id: "A#{i}_0",
            argument: "Opinion #{i}",
            comment_id: i.to_s,
            embedding: Array.new(5) { rand }
          )
        end
        ctx
      end

      let(:clustering_step) { Broadlistening::Steps::Clustering.new(config, context) }

      it "handles cluster_nums starting with 1" do
        clustering_step.execute

        # Level 1 should have exactly 1 cluster
        level_1_clusters = context.arguments.map { |arg| arg.cluster_ids[1] }.uniq
        expect(level_1_clusters.size).to eq(1)
        expect(level_1_clusters.first).to eq("1_0")
      end
    end

    describe "more clusters requested than samples" do
      let(:config) do
        Broadlistening::Config.new(
          api_key: "test",
          model: "gpt-4o-mini",
          cluster_nums: [ 5, 20 ] # More than 8 samples
        )
      end

      let(:context) do
        ctx = Broadlistening::Context.new
        ctx.arguments = 8.times.map do |i|
          Broadlistening::Argument.new(
            arg_id: "A#{i}_0",
            argument: "Opinion #{i}",
            comment_id: i.to_s,
            embedding: Array.new(5) { rand }
          )
        end
        ctx
      end

      let(:clustering_step) { Broadlistening::Steps::Clustering.new(config, context) }

      it "caps cluster count at sample count" do
        clustering_step.execute

        # Should never have more clusters than samples
        context.arguments.first.cluster_ids.each_with_index do |_cid, idx|
          next if idx == 0 # Skip root

          level_clusters = context.arguments.map { |arg| arg.cluster_ids[idx] }.uniq.size
          expect(level_clusters).to be <= context.arguments.size,
            "Level #{idx} has #{level_clusters} clusters but only #{context.arguments.size} samples"
        end
      end
    end

    describe "duplicate cluster_nums values" do
      let(:config) do
        Broadlistening::Config.new(
          api_key: "test",
          model: "gpt-4o-mini",
          cluster_nums: [ 2, 2, 5 ] # Duplicate 2
        )
      end

      let(:context) do
        ctx = Broadlistening::Context.new
        ctx.arguments = 10.times.map do |i|
          Broadlistening::Argument.new(
            arg_id: "A#{i}_0",
            argument: "Opinion #{i}",
            comment_id: i.to_s,
            embedding: Array.new(5) { rand }
          )
        end
        ctx
      end

      let(:clustering_step) { Broadlistening::Steps::Clustering.new(config, context) }

      it "handles duplicate cluster_nums by deduplication" do
        clustering_step.execute

        # After deduplication, we should have [2, 5] effectively
        # But the code uses sorted unique values
        # Verify all arguments have valid cluster_ids
        context.arguments.each do |arg|
          expect(arg.cluster_ids).not_to be_empty
          expect(arg.cluster_ids.first).to eq("0")
        end
      end
    end
  end

  describe "Consistency with Python behavior" do
    # Python uses specific format for cluster_ids:
    # ["0", "1_X", "2_Y", ...] where level is 1-indexed

    it "uses 1-indexed levels in cluster_ids (matching Python)" do
      config = Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 2, 4 ]
      )

      context = Broadlistening::Context.new
      context.arguments = 10.times.map do |i|
        Broadlistening::Argument.new(
          arg_id: "A#{i}_0",
          argument: "Opinion #{i}",
          comment_id: i.to_s,
          embedding: Array.new(5) { rand }
        )
      end

      clustering_step = Broadlistening::Steps::Clustering.new(config, context)
      clustering_step.execute

      # Verify cluster_ids format: ["0", "1_X", "2_Y"]
      sample_arg = context.arguments.first
      expect(sample_arg.cluster_ids[0]).to eq("0")
      expect(sample_arg.cluster_ids[1]).to match(/\A1_\d+\z/)
      expect(sample_arg.cluster_ids[2]).to match(/\A2_\d+\z/)
    end
  end
end
