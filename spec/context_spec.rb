# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'
require 'csv'

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
      expect(context.cluster_results).to be_empty
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

    context 'when extraction output exists (CSV format)' do
      before do
        FileUtils.mkdir_p(output_dir)
        # args.csv
        CSV.open(File.join(output_dir, 'args.csv'), 'w') do |csv|
          csv << [ 'arg-id', 'argument' ]
          csv << [ 'A1_0', 'test argument' ]
        end
        # relations.csv
        CSV.open(File.join(output_dir, 'relations.csv'), 'w') do |csv|
          csv << [ 'arg-id', 'comment-id' ]
          csv << [ 'A1_0', '1' ]
        end
      end

      it 'loads extraction data from CSV' do
        context = described_class.load_from_dir(output_dir)

        expect(context.arguments.size).to eq(1)
        expect(context.arguments.first).to be_a(Broadlistening::Argument)
        expect(context.arguments.first.arg_id).to eq('A1_0')
        expect(context.arguments.first.argument).to eq('test argument')
        expect(context.arguments.first.comment_id).to eq('1')
        expect(context.relations.size).to eq(1)
      end
    end

    context 'when embedding output exists (JSON format)' do
      before do
        FileUtils.mkdir_p(output_dir)
        # First create args.csv and relations.csv
        CSV.open(File.join(output_dir, 'args.csv'), 'w') do |csv|
          csv << [ 'arg-id', 'argument' ]
          csv << [ 'A1_0', 'test' ]
        end
        CSV.open(File.join(output_dir, 'relations.csv'), 'w') do |csv|
          csv << [ 'arg-id', 'comment-id' ]
          csv << [ 'A1_0', '1' ]
        end
        # embeddings.json (kept as JSON)
        File.write(File.join(output_dir, 'embeddings.json'), {
          arguments: [ { arg_id: 'A1_0', embedding: [ 0.1, 0.2, 0.3 ] } ]
        }.to_json)
      end

      it 'merges embedding data into arguments' do
        context = described_class.load_from_dir(output_dir)

        expect(context.arguments.first.embedding).to eq([ 0.1, 0.2, 0.3 ])
      end
    end

    context 'when clustering output exists (CSV format)' do
      before do
        FileUtils.mkdir_p(output_dir)
        # First create args.csv and relations.csv
        CSV.open(File.join(output_dir, 'args.csv'), 'w') do |csv|
          csv << [ 'arg-id', 'argument' ]
          csv << [ 'A1_0', 'test' ]
        end
        CSV.open(File.join(output_dir, 'relations.csv'), 'w') do |csv|
          csv << [ 'arg-id', 'comment-id' ]
          csv << [ 'A1_0', '1' ]
        end
        # hierarchical_clusters.csv
        CSV.open(File.join(output_dir, 'hierarchical_clusters.csv'), 'w') do |csv|
          csv << [ 'arg-id', 'argument', 'x', 'y', 'cluster-level-1-id', 'cluster-level-2-id' ]
          csv << [ 'A1_0', 'test', '0.5', '0.6', '1_0', '2_0' ]
        end
      end

      it 'loads clustering data and merges into arguments' do
        context = described_class.load_from_dir(output_dir)

        expect(context.arguments.first.x).to eq(0.5)
        expect(context.arguments.first.y).to eq(0.6)
        expect(context.arguments.first.cluster_ids).to eq(%w[0 1_0 2_0])
      end
    end

    context 'when labelling outputs exist (CSV format)' do
      before do
        FileUtils.mkdir_p(output_dir)
        # First create args.csv and relations.csv
        CSV.open(File.join(output_dir, 'args.csv'), 'w') do |csv|
          csv << [ 'arg-id', 'argument' ]
          csv << [ 'A1_0', 'test' ]
        end
        CSV.open(File.join(output_dir, 'relations.csv'), 'w') do |csv|
          csv << [ 'arg-id', 'comment-id' ]
          csv << [ 'A1_0', '1' ]
        end
        # hierarchical_initial_labels.csv
        CSV.open(File.join(output_dir, 'hierarchical_initial_labels.csv'), 'w') do |csv|
          csv << [ 'arg-id', 'argument', 'x', 'y', 'cluster-level-1-id', 'cluster-level-1-label',
                  'cluster-level-1-description', 'cluster-level-2-id', 'cluster-level-2-label', 'cluster-level-2-description' ]
          csv << [ 'A1_0', 'test', '0.5', '0.6', '1_0', 'Parent', 'Parent desc', '2_0', 'Test', 'Desc' ]
        end
        # hierarchical_merge_labels.csv
        CSV.open(File.join(output_dir, 'hierarchical_merge_labels.csv'), 'w') do |csv|
          csv << [ 'level', 'id', 'label', 'description', 'value', 'parent', 'density', 'density_rank',
                  'density_rank_percentile' ]
          csv << [ '1', '1_0', 'Parent', 'Parent desc', '1', '0', '', '', '' ]
          csv << [ '2', '2_0', 'Test', 'Desc', '1', '1_0', '', '', '' ]
        end
      end

      it 'loads labelling data from CSV' do
        context = described_class.load_from_dir(output_dir)

        expect(context.initial_labels).to have_key('2_0')
        expect(context.initial_labels['2_0'].label).to eq('Test')
        expect(context.labels).to have_key('1_0')
        expect(context.labels['1_0'].label).to eq('Parent')
      end
    end

    context 'when overview output exists (TXT format)' do
      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'hierarchical_overview.txt'), 'This is a test overview.')
      end

      it 'loads overview data from TXT' do
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
      ctx.relations = [ Broadlistening::Relation.new(arg_id: 'A1_0', comment_id: '1') ]
      ctx
    end

    it 'saves extraction output as CSV' do
      context.save_step(:extraction, output_dir)

      args_path = File.join(output_dir, 'args.csv')
      relations_path = File.join(output_dir, 'relations.csv')

      expect(File.exist?(args_path)).to be true
      expect(File.exist?(relations_path)).to be true

      args_data = CSV.read(args_path, headers: true)
      expect(args_data.first['arg-id']).to eq('A1_0')
      expect(args_data.first['argument']).to eq('test')

      relations_data = CSV.read(relations_path, headers: true)
      expect(relations_data.first['arg-id']).to eq('A1_0')
      expect(relations_data.first['comment-id']).to eq('1')
    end

    it 'saves embedding output as JSON with only relevant fields' do
      context.save_step(:embedding, output_dir)

      file_path = File.join(output_dir, 'embeddings.json')
      data = JSON.parse(File.read(file_path), symbolize_names: true)

      expect(data[:arguments].first.keys).to contain_exactly(:arg_id, :embedding)
    end

    it 'saves clustering output as CSV' do
      context.cluster_results = Broadlistening::ClusterResults.from_h({ 1 => [ 0 ] })
      context.save_step(:clustering, output_dir)

      file_path = File.join(output_dir, 'hierarchical_clusters.csv')
      expect(File.exist?(file_path)).to be true

      data = CSV.read(file_path, headers: true)
      expect(data.first['arg-id']).to eq('A1_0')
      expect(data.first['x']).to eq('0.5')
      expect(data.first['y']).to eq('0.6')
      expect(data.first['cluster-level-1-id']).to eq('1_0')
    end

    it 'creates output directory if needed' do
      new_dir = File.join(output_dir, 'nested', 'dir')

      context.save_step(:extraction, new_dir)

      expect(File.exist?(File.join(new_dir, 'args.csv'))).to be true
      expect(File.exist?(File.join(new_dir, 'relations.csv'))).to be true
    end

    it 'saves overview as TXT' do
      context.instance_variable_set(:@overview, 'Test overview text')
      context.save_step(:overview, output_dir)

      file_path = File.join(output_dir, 'hierarchical_overview.txt')
      expect(File.exist?(file_path)).to be true
      expect(File.read(file_path)).to eq('Test overview text')
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
