# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Floating Point Precision Compatibility" do
  # Tests to verify floating point handling between Python and Ruby implementations

  let(:fixtures_dir) { File.expand_path("fixtures/polis", __dir__) }

  let(:python_result) do
    JSON.parse(File.read(File.join(fixtures_dir, "hierarchical_result.json")))
  end

  describe "Coordinate precision in Python output" do
    let(:python_coordinates) do
      python_result["arguments"].map { |a| [ a["x"], a["y"] ] }
    end

    it "x coordinates are valid floats" do
      python_result["arguments"].each do |arg|
        expect(arg["x"]).to be_a(Numeric)
        expect(arg["x"].finite?).to be true
      end
    end

    it "y coordinates are valid floats" do
      python_result["arguments"].each do |arg|
        expect(arg["y"]).to be_a(Numeric)
        expect(arg["y"].finite?).to be true
      end
    end

    it "coordinates have reasonable precision" do
      # JSON typically preserves ~15-17 significant digits for floats
      python_result["arguments"].take(10).each do |arg|
        x_str = arg["x"].to_s
        y_str = arg["y"].to_s

        # Should not have excessive decimal places after JSON parsing
        expect(x_str.length).to be < 25
        expect(y_str.length).to be < 25
      end
    end
  end

  describe "Ruby floating point handling" do
    let(:config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 2, 5 ]
      )
    end

    describe "Argument coordinates" do
      let(:arguments) do
        [
          Broadlistening::Argument.new(
            arg_id: "A1_0",
            argument: "Test",
            comment_id: "1",
            x: 1.2345678901234567,
            y: -9.8765432109876543,
            cluster_ids: %w[0 1_0]
          ),
          Broadlistening::Argument.new(
            arg_id: "A2_0",
            argument: "Test",
            comment_id: "2",
            x: Float::MIN,
            y: Float::MAX,
            cluster_ids: %w[0 1_0]
          ),
          Broadlistening::Argument.new(
            arg_id: "A3_0",
            argument: "Test",
            comment_id: "3",
            x: 0.0,
            y: -0.0,
            cluster_ids: %w[0 1_0]
          )
        ]
      end

      let(:context) do
        ctx = Broadlistening::Context.new
        ctx.comments = [
          Broadlistening::Comment.new(id: "1", body: "C1", proposal_id: "test"),
          Broadlistening::Comment.new(id: "2", body: "C2", proposal_id: "test"),
          Broadlistening::Comment.new(id: "3", body: "C3", proposal_id: "test")
        ]
        ctx.arguments = arguments
        ctx.labels = { "1_0" => Broadlistening::ClusterLabel.new(cluster_id: "1_0", level: 1, label: "L", description: "D") }
        ctx.cluster_results = { 1 => [ 0, 0, 0 ] }
        ctx.overview = "Overview"
        ctx
      end

      it "preserves high precision coordinates" do
        step = Broadlistening::Steps::Aggregation.new(config, context)
        step.execute

        result_h = context.result.to_h
        arg = result_h[:arguments].find { |a| a[:arg_id] == "A1_0" }
        expect(arg[:x]).to be_within(1e-10).of(1.2345678901234567)
        expect(arg[:y]).to be_within(1e-10).of(-9.8765432109876543)
      end

      it "handles zero values" do
        step = Broadlistening::Steps::Aggregation.new(config, context)
        step.execute

        result_h = context.result.to_h
        arg = result_h[:arguments].find { |a| a[:arg_id] == "A3_0" }
        expect(arg[:x]).to eq(0.0)
        expect(arg[:y]).to eq(0.0)
      end

      it "serializes to valid JSON" do
        step = Broadlistening::Steps::Aggregation.new(config, context)
        step.execute

        json_str = JSON.generate(context.result.to_h)
        parsed = JSON.parse(json_str)

        parsed["arguments"].each do |arg|
          expect(arg["x"]).to be_a(Numeric)
          expect(arg["y"]).to be_a(Numeric)
          expect(arg["x"].finite?).to be true unless arg["x"].nil?
          expect(arg["y"].finite?).to be true unless arg["y"].nil?
        end
      end
    end

    describe "Numo::NArray precision" do
      it "maintains precision through DFloat operations" do
        original = [ 1.2345678901234567, -9.8765432109876543 ]
        array = Numo::DFloat.cast(original)

        expect(array[0]).to be_within(1e-15).of(original[0])
        expect(array[1]).to be_within(1e-15).of(original[1])
      end

      it "maintains precision through SFloat operations" do
        original = [ 1.234567, -9.876543 ]
        array = Numo::SFloat.cast(original)

        # SFloat has less precision (~7 significant digits)
        expect(array[0]).to be_within(1e-5).of(original[0])
        expect(array[1]).to be_within(1e-5).of(original[1])
      end
    end
  end

  describe "JSON round-trip precision" do
    it "preserves precision through JSON serialization" do
      original = {
        x: 1.2345678901234567,
        y: -9.8765432109876543,
        z: 0.0
      }

      json_str = JSON.generate(original)
      parsed = JSON.parse(json_str, symbolize_names: true)

      # JSON preserves about 15-17 significant digits
      expect(parsed[:x]).to be_within(1e-14).of(original[:x])
      expect(parsed[:y]).to be_within(1e-14).of(original[:y])
      expect(parsed[:z]).to eq(0.0)
    end

    it "handles scientific notation" do
      original = { small: 1.23e-10, large: 9.87e10 }

      json_str = JSON.generate(original)
      parsed = JSON.parse(json_str, symbolize_names: true)

      expect(parsed[:small]).to be_within(1e-20).of(original[:small])
      expect(parsed[:large]).to be_within(1e5).of(original[:large])
    end
  end

  describe "Comparison between Python and Ruby coordinates" do
    let(:python_args) { python_result["arguments"] }

    it "Python coordinates are within reasonable range" do
      x_values = python_args.map { |a| a["x"] }
      y_values = python_args.map { |a| a["y"] }

      # UMAP typically produces coordinates in a reasonable range
      expect(x_values.min).to be > -100
      expect(x_values.max).to be < 100
      expect(y_values.min).to be > -100
      expect(y_values.max).to be < 100
    end

    it "no NaN or Infinity values in Python output" do
      python_args.each do |arg|
        expect(arg["x"].to_f.nan?).to be false
        expect(arg["y"].to_f.nan?).to be false
        expect(arg["x"].to_f.infinite?).to be_nil
        expect(arg["y"].to_f.infinite?).to be_nil
      end
    end
  end

  describe "Cluster value integer handling" do
    it "Python cluster values are integers" do
      python_result["clusters"].each do |cluster|
        expect(cluster["value"]).to be_a(Integer)
        expect(cluster["value"]).to be >= 0
      end
    end

    it "Python cluster levels are integers" do
      python_result["clusters"].each do |cluster|
        expect(cluster["level"]).to be_a(Integer)
        expect(cluster["level"]).to be >= 0
      end
    end
  end

  describe "Type consistency in aggregation output" do
    let(:config) do
      Broadlistening::Config.new(
        api_key: "test",
        model: "gpt-4o-mini",
        cluster_nums: [ 2, 5 ]
      )
    end

    let(:arguments) do
      [
        Broadlistening::Argument.new(
          arg_id: "A1_0",
          argument: "Test",
          comment_id: "1",
          x: 1.5,
          y: 2.5,
          cluster_ids: %w[0 1_0 2_0]
        ),
        Broadlistening::Argument.new(
          arg_id: "A2_0",
          argument: "Test2",
          comment_id: "2",
          x: -1.5,
          y: -2.5,
          cluster_ids: %w[0 1_0 2_1]
        )
      ]
    end

    let(:context) do
      ctx = Broadlistening::Context.new
      ctx.comments = [
        Broadlistening::Comment.new(id: "1", body: "C1", proposal_id: "test"),
        Broadlistening::Comment.new(id: "2", body: "C2", proposal_id: "test")
      ]
      ctx.arguments = arguments
      ctx.labels = {
        "1_0" => Broadlistening::ClusterLabel.new(cluster_id: "1_0", level: 1, label: "L1", description: "D1"),
        "2_0" => Broadlistening::ClusterLabel.new(cluster_id: "2_0", level: 2, label: "L2a", description: "D2a"),
        "2_1" => Broadlistening::ClusterLabel.new(cluster_id: "2_1", level: 2, label: "L2b", description: "D2b")
      }
      ctx.cluster_results = { 1 => [ 0, 0 ], 2 => [ 0, 1 ] }
      ctx.overview = "Overview"
      ctx
    end

    it "produces correct types in output" do
      step = Broadlistening::Steps::Aggregation.new(config, context)
      step.execute

      result = context.result.to_h

      # Arguments
      result[:arguments].each do |arg|
        expect(arg[:arg_id]).to be_a(String)
        expect(arg[:argument]).to be_a(String)
        expect(arg[:comment_id]).to be_a(Integer)
        expect(arg[:x]).to be_a(Float)
        expect(arg[:y]).to be_a(Float)
        expect(arg[:p]).to be_a(Integer)
        expect(arg[:cluster_ids]).to be_an(Array)
        arg[:cluster_ids].each { |cid| expect(cid).to be_a(String) }
      end

      # Clusters
      result[:clusters].each do |cluster|
        expect(cluster[:level]).to be_a(Integer)
        expect(cluster[:id]).to be_a(String)
        expect(cluster[:label]).to be_a(String)
        expect(cluster[:takeaway]).to be_a(String)
        expect(cluster[:value]).to be_a(Integer)
        expect(cluster[:parent]).to be_a(String)
      end
    end
  end
end
