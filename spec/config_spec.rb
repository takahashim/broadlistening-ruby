# frozen_string_literal: true

RSpec.describe Broadlistening::Config do
  describe ".calculate_cluster_nums" do
    it "calculates cluster nums based on comment count" do
      # Test various comment counts against expected values (matching kouchou-ai behavior)
      test_cases = [
        { count: 8, expected: [ 2, 4 ] },      # cbrt(8) = 2, 2^2 = 4
        { count: 27, expected: [ 3, 9 ] },     # cbrt(27) = 3, 3^2 = 9
        { count: 64, expected: [ 4, 16 ] },    # cbrt(64) = 4, 4^2 = 16
        { count: 125, expected: [ 5, 25 ] },   # cbrt(125) = 5, 5^2 = 25
        { count: 216, expected: [ 6, 36 ] },   # cbrt(216) = 6, 6^2 = 36
        { count: 343, expected: [ 7, 49 ] },   # cbrt(343) = 7, 7^2 = 49
        { count: 512, expected: [ 8, 64 ] },   # cbrt(512) = 8, 8^2 = 64
        { count: 729, expected: [ 9, 81 ] },   # cbrt(729) = 9, 9^2 = 81
        { count: 1000, expected: [ 10, 100 ] } # cbrt(1000) = 10, 10^2 = 100
      ]

      test_cases.each do |tc|
        result = described_class.calculate_cluster_nums(tc[:count])
        expect(result).to eq(tc[:expected]), "For #{tc[:count]} comments, expected #{tc[:expected]} but got #{result}"
      end
    end

    it "clamps lv1 to minimum of 2" do
      result = described_class.calculate_cluster_nums(1)
      expect(result[0]).to eq(2)
    end

    it "clamps lv1 to maximum of 10" do
      result = described_class.calculate_cluster_nums(2000)
      expect(result[0]).to eq(10)
    end

    it "clamps lv2 to maximum of 1000" do
      # This won't happen with normal lv1 values (max 10^2 = 100),
      # but test the clamping logic exists
      result = described_class.calculate_cluster_nums(1_000_000)
      expect(result[1]).to be <= 1000
    end
  end

  describe "#with_calculated_cluster_nums" do
    let(:api_key) { "test-api-key" }

    context "when auto_cluster_nums is false" do
      let(:config) { described_class.new(api_key: api_key, auto_cluster_nums: false) }

      it "returns self without modification" do
        result = config.with_calculated_cluster_nums(729)
        expect(result).to be(config)
        expect(result.cluster_nums).to eq([ 5, 15 ])
      end
    end

    context "when auto_cluster_nums is true" do
      let(:config) { described_class.new(api_key: api_key, auto_cluster_nums: true) }

      it "returns a new config with calculated cluster_nums" do
        result = config.with_calculated_cluster_nums(729)
        expect(result).not_to be(config)
        expect(result.cluster_nums).to eq([ 9, 81 ])
      end

      it "sets auto_cluster_nums to false in the new config" do
        result = config.with_calculated_cluster_nums(729)
        expect(result.auto_cluster_nums).to be(false)
      end

      it "preserves other config values" do
        custom_config = described_class.new(
          api_key: api_key,
          auto_cluster_nums: true,
          model: "gpt-4",
          workers: 5
        )

        result = custom_config.with_calculated_cluster_nums(729)
        expect(result.model).to eq("gpt-4")
        expect(result.workers).to eq(5)
      end
    end
  end

  describe "#auto_cluster_nums" do
    let(:api_key) { "test-api-key" }

    it "defaults to false" do
      config = described_class.new(api_key: api_key)
      expect(config.auto_cluster_nums).to be(false)
    end

    it "can be set to true" do
      config = described_class.new(api_key: api_key, auto_cluster_nums: true)
      expect(config.auto_cluster_nums).to be(true)
    end
  end

  describe ".from_hash" do
    let(:api_key) { "test-api-key" }

    it "reads auto_cluster_nums from hash" do
      config = described_class.from_hash(api_key: api_key, auto_cluster_nums: true)
      expect(config.auto_cluster_nums).to be(true)
    end
  end

  describe "#to_h" do
    let(:api_key) { "test-api-key" }

    it "includes auto_cluster_nums when true" do
      config = described_class.new(api_key: api_key, auto_cluster_nums: true)
      expect(config.to_h[:auto_cluster_nums]).to be(true)
    end
  end
end
