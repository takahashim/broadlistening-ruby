# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Broadlistening::SpecLoader do
  let(:specs_json) do
    <<~JSON
      [
        {
          "step": "extraction",
          "filename": "args.csv",
          "dependencies": {"params": ["limit"], "steps": []},
          "use_llm": true
        },
        {
          "step": "embedding",
          "filename": "embeddings.pkl",
          "dependencies": {"params": ["model"], "steps": ["extraction"]}
        },
        {
          "step": "hierarchical_clustering",
          "filename": "hierarchical_clusters.csv",
          "dependencies": {"params": ["cluster_nums"], "steps": ["embedding"]}
        },
        {
          "step": "hierarchical_initial_labelling",
          "filename": "hierarchical_initial_labels.csv",
          "dependencies": {"params": ["sampling_num"], "steps": ["hierarchical_clustering"]},
          "use_llm": true
        },
        {
          "step": "hierarchical_merge_labelling",
          "filename": "hierarchical_merge_labels.csv",
          "dependencies": {"params": [], "steps": ["hierarchical_initial_labelling"]},
          "use_llm": true
        },
        {
          "step": "hierarchical_overview",
          "filename": "hierarchical_overview.txt",
          "dependencies": {"params": [], "steps": ["hierarchical_merge_labelling"]},
          "use_llm": true
        },
        {
          "step": "hierarchical_aggregation",
          "filename": "hierarchical_result.json",
          "dependencies": {"params": [], "steps": ["hierarchical_overview"]}
        },
        {
          "step": "hierarchical_visualization",
          "filename": "report",
          "dependencies": {"params": [], "steps": ["hierarchical_aggregation"]}
        }
      ]
    JSON
  end

  let(:specs_file) do
    file = Tempfile.new([ 'specs', '.json' ])
    file.write(specs_json)
    file.close
    file
  end

  after do
    specs_file.unlink
  end

  subject(:loader) { described_class.new(specs_file.path) }

  describe '#initialize' do
    it 'loads and converts specs from JSON file' do
      expect(loader.specs).to be_an(Array)
      expect(loader.specs.size).to eq(7) # hierarchical_visualization is skipped
    end
  end

  describe '#steps' do
    it 'returns list of step names' do
      expect(loader.steps).to eq(%i[
                                   extraction
                                   embedding
                                   clustering
                                   initial_labelling
                                   merge_labelling
                                   overview
                                   aggregation
                                 ])
    end
  end

  describe '#find' do
    it 'finds spec by step name' do
      spec = loader.find(:extraction)
      expect(spec[:step]).to eq(:extraction)
      expect(spec[:output_file]).to eq('extraction.json')
    end

    it 'returns nil for unknown step' do
      expect(loader.find(:unknown)).to be_nil
    end
  end

  describe 'step mapping' do
    it 'maps Python step names to Ruby step names' do
      expect(loader.find(:clustering)[:step]).to eq(:clustering)
      expect(loader.find(:initial_labelling)[:step]).to eq(:initial_labelling)
      expect(loader.find(:merge_labelling)[:step]).to eq(:merge_labelling)
      expect(loader.find(:overview)[:step]).to eq(:overview)
      expect(loader.find(:aggregation)[:step]).to eq(:aggregation)
    end

    it 'skips hierarchical_visualization step' do
      expect(loader.find(:visualization)).to be_nil
      expect(loader.steps).not_to include(:visualization)
    end
  end

  describe 'output file mapping' do
    it 'uses Ruby gem specific output file names' do
      expect(loader.find(:extraction)[:output_file]).to eq('extraction.json')
      expect(loader.find(:embedding)[:output_file]).to eq('embeddings.json')
      expect(loader.find(:clustering)[:output_file]).to eq('clustering.json')
      expect(loader.find(:initial_labelling)[:output_file]).to eq('initial_labels.json')
      expect(loader.find(:merge_labelling)[:output_file]).to eq('merge_labels.json')
      expect(loader.find(:overview)[:output_file]).to eq('overview.json')
      expect(loader.find(:aggregation)[:output_file]).to eq('result.json')
    end
  end

  describe 'dependencies conversion' do
    it 'converts step dependencies from Python names to Ruby names' do
      spec = loader.find(:clustering)
      expect(spec[:dependencies][:steps]).to eq([ :embedding ])
    end

    it 'converts param dependencies to symbols' do
      spec = loader.find(:extraction)
      expect(spec[:dependencies][:params]).to include(:limit)
    end
  end

  describe 'use_llm handling' do
    it 'adds prompt and model to dependencies when use_llm is true' do
      spec = loader.find(:extraction)
      expect(spec[:use_llm]).to be true
      expect(spec[:dependencies][:params]).to include(:prompt)
      expect(spec[:dependencies][:params]).to include(:model)
    end

    it 'does not add prompt and model when use_llm is false' do
      spec = loader.find(:embedding)
      expect(spec[:use_llm]).to be false
      expect(spec[:dependencies][:params]).not_to include(:prompt)
    end

    it 'preserves original params and adds prompt/model' do
      spec = loader.find(:extraction)
      expect(spec[:dependencies][:params]).to include(:limit)
      expect(spec[:dependencies][:params]).to include(:prompt)
      expect(spec[:dependencies][:params]).to include(:model)
    end
  end

  describe '.default_specs_path' do
    it 'returns path from environment variable if set' do
      allow(ENV).to receive(:fetch).with('BROADLISTENING_SPECS_PATH').and_return('/custom/path.json')
      expect(described_class.default_specs_path).to eq('/custom/path.json')
    end
  end
end
