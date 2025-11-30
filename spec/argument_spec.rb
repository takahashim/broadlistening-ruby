# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Broadlistening::Argument do
  describe '.from_hash' do
    it 'creates argument from hash with symbol keys' do
      hash = {
        arg_id: 'A1_0',
        argument: 'Test opinion',
        comment_id: '1',
        embedding: [ 0.1, 0.2 ],
        x: 0.5,
        y: 0.6,
        cluster_ids: %w[0 1_0],
        attributes: { 'age' => '30代' },
        url: 'https://example.com',
        properties: { 'source' => 'twitter' }
      }

      arg = described_class.from_hash(hash)

      expect(arg.arg_id).to eq('A1_0')
      expect(arg.argument).to eq('Test opinion')
      expect(arg.comment_id).to eq('1')
      expect(arg.embedding).to eq([ 0.1, 0.2 ])
      expect(arg.x).to eq(0.5)
      expect(arg.y).to eq(0.6)
      expect(arg.cluster_ids).to eq(%w[0 1_0])
      expect(arg.attributes).to eq({ 'age' => '30代' })
      expect(arg.url).to eq('https://example.com')
      expect(arg.properties).to eq({ 'source' => 'twitter' })
    end

    it 'creates argument from hash with string keys' do
      hash = {
        'arg_id' => 'A1_0',
        'argument' => 'Test opinion',
        'comment_id' => '1'
      }

      arg = described_class.from_hash(hash)

      expect(arg.arg_id).to eq('A1_0')
      expect(arg.argument).to eq('Test opinion')
      expect(arg.comment_id).to eq('1')
    end
  end

  describe '.from_comment' do
    let(:comment) do
      Broadlistening::Comment.new(
        id: '1',
        body: 'Test body',
        proposal_id: '123',
        source_url: 'https://example.com',
        attributes: { 'age' => '30代' },
        properties: { 'source' => 'twitter' }
      )
    end

    it 'creates argument from comment' do
      arg = described_class.from_comment(comment, 'Extracted opinion', 0)

      expect(arg.arg_id).to eq('A1_0')
      expect(arg.argument).to eq('Extracted opinion')
      expect(arg.comment_id).to eq('1')
      expect(arg.attributes).to eq({ 'age' => '30代' })
      expect(arg.url).to eq('https://example.com')
      expect(arg.properties).to eq({ 'source' => 'twitter' })
    end

    it 'creates second argument with correct index' do
      arg = described_class.from_comment(comment, 'Second opinion', 1)

      expect(arg.arg_id).to eq('A1_1')
    end
  end

  describe '#to_h' do
    it 'returns hash representation with compact nil values' do
      arg = described_class.new(
        arg_id: 'A1_0',
        argument: 'Test',
        comment_id: '1'
      )

      hash = arg.to_h

      expect(hash[:arg_id]).to eq('A1_0')
      expect(hash[:argument]).to eq('Test')
      expect(hash[:comment_id]).to eq('1')
      expect(hash).not_to have_key(:embedding)
      expect(hash).not_to have_key(:x)
    end

    it 'includes non-nil optional fields' do
      arg = described_class.new(
        arg_id: 'A1_0',
        argument: 'Test',
        comment_id: '1',
        embedding: [ 0.1, 0.2 ],
        x: 0.5,
        y: 0.6
      )

      hash = arg.to_h

      expect(hash[:embedding]).to eq([ 0.1, 0.2 ])
      expect(hash[:x]).to eq(0.5)
      expect(hash[:y]).to eq(0.6)
    end
  end

  describe '#to_embedding_h' do
    it 'returns only arg_id and embedding' do
      arg = described_class.new(
        arg_id: 'A1_0',
        argument: 'Test',
        comment_id: '1',
        embedding: [ 0.1, 0.2 ],
        x: 0.5
      )

      hash = arg.to_embedding_h

      expect(hash).to eq({ arg_id: 'A1_0', embedding: [ 0.1, 0.2 ] })
    end
  end

  describe '#to_clustering_h' do
    it 'returns only clustering-related fields' do
      arg = described_class.new(
        arg_id: 'A1_0',
        argument: 'Test',
        comment_id: '1',
        x: 0.5,
        y: 0.6,
        cluster_ids: %w[0 1_0]
      )

      hash = arg.to_clustering_h

      expect(hash).to eq({
        arg_id: 'A1_0',
        x: 0.5,
        y: 0.6,
        cluster_ids: %w[0 1_0]
      })
    end
  end

  describe '#in_cluster?' do
    let(:arg) do
      described_class.new(
        arg_id: 'A1_0',
        argument: 'Test',
        comment_id: '1',
        cluster_ids: %w[0 1_0 2_1]
      )
    end

    it 'returns true when in cluster' do
      expect(arg.in_cluster?('1_0')).to be true
      expect(arg.in_cluster?('2_1')).to be true
    end

    it 'returns false when not in cluster' do
      expect(arg.in_cluster?('1_1')).to be false
      expect(arg.in_cluster?('3_0')).to be false
    end

    it 'returns false when cluster_ids is nil' do
      arg = described_class.new(arg_id: 'A1_0', argument: 'Test', comment_id: '1')

      expect(arg.in_cluster?('1_0')).to be false
    end
  end

  describe '#comment_id_int' do
    it 'returns comment_id as integer' do
      arg = described_class.new(arg_id: 'A1_0', argument: 'Test', comment_id: '42')

      expect(arg.comment_id_int).to eq(42)
    end

    it 'extracts from arg_id when comment_id is nil' do
      arg = described_class.new(arg_id: 'A123_0', argument: 'Test', comment_id: nil)

      expect(arg.comment_id_int).to eq(123)
    end

    it 'returns 0 when cannot extract' do
      arg = described_class.new(arg_id: 'invalid', argument: 'Test', comment_id: nil)

      expect(arg.comment_id_int).to eq(0)
    end
  end
end
