# frozen_string_literal: true

RSpec.describe Broadlistening::Cli::Options do
  describe "#initialize" do
    it "has default values" do
      options = described_class.new

      expect(options.config_path).to be_nil
      expect(options.force).to be false
      expect(options.only).to be_nil
      expect(options.skip_interaction).to be false
      expect(options.from_step).to be_nil
      expect(options.input_dir).to be_nil
    end
  end

  describe "#to_pipeline_options" do
    it "returns hash with non-nil values" do
      options = described_class.new
      options.force = true
      options.only = :extraction

      result = options.to_pipeline_options

      expect(result).to eq(force: true, only: :extraction)
    end

    it "excludes nil values" do
      options = described_class.new

      result = options.to_pipeline_options

      expect(result).to eq(force: false)
    end
  end

  describe "#resume_mode?" do
    it "returns true when from_step is set" do
      options = described_class.new
      options.from_step = :embedding

      expect(options.resume_mode?).to be true
    end

    it "returns true when input_dir is set" do
      options = described_class.new
      options.input_dir = "/tmp/input"

      expect(options.resume_mode?).to be true
    end

    it "returns false when neither is set" do
      options = described_class.new

      expect(options.resume_mode?).to be false
    end
  end

  describe "#from_step_without_input_dir?" do
    it "returns true when from_step is set but input_dir is not" do
      options = described_class.new
      options.from_step = :embedding

      expect(options.from_step_without_input_dir?).to be true
    end

    it "returns false when both are set" do
      options = described_class.new
      options.from_step = :embedding
      options.input_dir = "/tmp/input"

      expect(options.from_step_without_input_dir?).to be false
    end
  end

  describe "#input_dir_without_from_step?" do
    it "returns true when input_dir is set but from_step is not" do
      options = described_class.new
      options.input_dir = "/tmp/input"

      expect(options.input_dir_without_from_step?).to be true
    end

    it "returns false when both are set" do
      options = described_class.new
      options.from_step = :embedding
      options.input_dir = "/tmp/input"

      expect(options.input_dir_without_from_step?).to be false
    end
  end

  describe "#conflicting_options?" do
    it "returns true when both from_step and only are set" do
      options = described_class.new
      options.from_step = :embedding
      options.only = :extraction

      expect(options.conflicting_options?).to be true
    end

    it "returns false when only from_step is set" do
      options = described_class.new
      options.from_step = :embedding

      expect(options.conflicting_options?).to be false
    end

    it "returns false when only only is set" do
      options = described_class.new
      options.only = :extraction

      expect(options.conflicting_options?).to be false
    end
  end
end
