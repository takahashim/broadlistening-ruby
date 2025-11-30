# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe Broadlistening::Context do
  let(:output_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe '#initialize' do
    it 'initializes with empty collections' do
      context = described_class.new

      expect(context.comments).to eq([])
      expect(context.arguments).to eq([])
      expect(context.relations).to eq([])
      expect(context.cluster_results).to eq({})
      expect(context.initial_labels).to eq({})
      expect(context.labels).to eq({})
      expect(context.overview).to be_nil
      expect(context.result).to be_nil
    end
  end

  describe '.load_from_dir' do
    context 'when no output files exist' do
      it 'returns a new empty context' do
        context = described_class.load_from_dir(output_dir)

        expect(context).to be_a(described_class)
        expect(context.comments).to eq([])
      end
    end

    context 'when extraction output exists' do
      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'extraction.json'), {
          comments: [ { id: '1', body: 'Test' } ],
          arguments: [ { arg_id: 'A1_0', argument: 'test', comment_id: '1' } ],
          relations: [ { arg_id: 'A1_0', comment_id: '1' } ]
        }.to_json)
      end

      it 'loads extraction data' do
        context = described_class.load_from_dir(output_dir)

        expect(context.comments.size).to eq(1)
        expect(context.comments.first).to be_a(Broadlistening::Comment)
        expect(context.comments.first.id).to eq('1')
        expect(context.arguments.size).to eq(1)
        expect(context.arguments.first).to be_a(Broadlistening::Argument)
        expect(context.arguments.first.arg_id).to eq('A1_0')
      end
    end

    context 'when embedding output exists' do
      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'extraction.json'), {
          arguments: [ { arg_id: 'A1_0', argument: 'test', comment_id: '1' } ]
        }.to_json)
        File.write(File.join(output_dir, 'embeddings.json'), {
          arguments: [ { arg_id: 'A1_0', embedding: [ 0.1, 0.2, 0.3 ] } ]
        }.to_json)
      end

      it 'merges embedding data into arguments' do
        context = described_class.load_from_dir(output_dir)

        expect(context.arguments.first.embedding).to eq([ 0.1, 0.2, 0.3 ])
      end
    end

    context 'when clustering output exists' do
      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'extraction.json'), {
          arguments: [ { arg_id: 'A1_0', argument: 'test', comment_id: '1' } ]
        }.to_json)
        File.write(File.join(output_dir, 'clustering.json'), {
          cluster_results: { 1 => [ 0 ], 2 => [ 0 ] },
          arguments: [ { arg_id: 'A1_0', x: 0.5, y: 0.6, cluster_ids: %w[0 1_0 2_0] } ]
        }.to_json)
      end

      it 'loads cluster_results and merges clustering data' do
        context = described_class.load_from_dir(output_dir)

        # Keys are symbolized when loading from JSON
        expect(context.cluster_results[:"1"]).to eq([ 0 ])
        expect(context.arguments.first.x).to eq(0.5)
        expect(context.arguments.first.y).to eq(0.6)
        expect(context.arguments.first.cluster_ids).to eq(%w[0 1_0 2_0])
      end
    end

    context 'when labelling outputs exist' do
      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'initial_labels.json'), {
          initial_labels: { '2_0' => { cluster_id: '2_0', level: 2, label: 'Test', description: 'Desc' } }
        }.to_json)
        File.write(File.join(output_dir, 'merge_labels.json'), {
          labels: { '1_0' => { cluster_id: '1_0', level: 1, label: 'Parent', description: 'Parent desc' } }
        }.to_json)
      end

      it 'loads labelling data' do
        context = described_class.load_from_dir(output_dir)

        expect(context.initial_labels).to have_key(:'2_0')
        expect(context.labels).to have_key(:'1_0')
      end
    end

    context 'when overview output exists' do
      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'overview.json'), {
          overview: 'This is a test overview.'
        }.to_json)
      end

      it 'loads overview data' do
        context = described_class.load_from_dir(output_dir)

        expect(context.overview).to eq('This is a test overview.')
      end
    end
  end

  describe '#save_step' do
    let(:context) do
      ctx = described_class.new
      ctx.comments = [ Broadlistening::Comment.new(id: '1', body: 'Test') ]
      ctx.arguments = [ Broadlistening::Argument.new(
        arg_id: 'A1_0',
        argument: 'test',
        comment_id: '1',
        embedding: [ 0.1, 0.2 ],
        x: 0.5,
        y: 0.6,
        cluster_ids: %w[0 1_0]
      ) ]
      ctx.relations = [ { arg_id: 'A1_0', comment_id: '1' } ]
      ctx
    end

    it 'saves extraction output' do
      context.save_step(:extraction, output_dir)

      file_path = File.join(output_dir, 'extraction.json')
      expect(File.exist?(file_path)).to be true

      data = JSON.parse(File.read(file_path), symbolize_names: true)
      expect(data[:comments].first[:id]).to eq('1')
      expect(data[:arguments].first[:arg_id]).to eq('A1_0')
    end

    it 'saves embedding output with only relevant fields' do
      context.save_step(:embedding, output_dir)

      file_path = File.join(output_dir, 'embeddings.json')
      data = JSON.parse(File.read(file_path), symbolize_names: true)

      expect(data[:arguments].first.keys).to contain_exactly(:arg_id, :embedding)
    end

    it 'saves clustering output with only relevant fields' do
      context.cluster_results = { 1 => [ 0 ] }
      context.save_step(:clustering, output_dir)

      file_path = File.join(output_dir, 'clustering.json')
      data = JSON.parse(File.read(file_path), symbolize_names: true)

      expect(data[:cluster_results]).to eq({ '1': [ 0 ] })
      expect(data[:arguments].first.keys).to contain_exactly(:arg_id, :x, :y, :cluster_ids)
    end

    it 'creates output directory if needed' do
      new_dir = File.join(output_dir, 'nested', 'dir')

      context.save_step(:extraction, new_dir)

      expect(File.exist?(File.join(new_dir, 'extraction.json'))).to be true
    end
  end

  describe '#to_h' do
    it 'converts context to hash' do
      context = described_class.new
      context.comments = [ Broadlistening::Comment.new(id: '1', body: 'Test') ]
      context.arguments = [ Broadlistening::Argument.new(arg_id: 'A1_0', argument: 'test', comment_id: '1') ]
      context.overview = 'Test overview'

      hash = context.to_h

      expect(hash[:comments].first[:id]).to eq('1')
      expect(hash[:arguments].first[:arg_id]).to eq('A1_0')
      expect(hash[:overview]).to eq('Test overview')
    end
  end
end
