# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Broadlistening::Comment do
  describe '.from_hash' do
    context 'with symbol keys' do
      it 'normalizes basic fields' do
        hash = { id: '1', body: 'Test comment', proposal_id: '123' }

        comment = described_class.from_hash(hash)

        expect(comment.id).to eq('1')
        expect(comment.body).to eq('Test comment')
        expect(comment.proposal_id).to eq('123')
      end
    end

    context 'with string keys' do
      it 'normalizes basic fields' do
        hash = { 'id' => '1', 'body' => 'Test comment', 'proposal_id' => '123' }

        comment = described_class.from_hash(hash)

        expect(comment.id).to eq('1')
        expect(comment.body).to eq('Test comment')
        expect(comment.proposal_id).to eq('123')
      end
    end

    context 'with source_url' do
      it 'extracts source_url with underscore' do
        hash = { id: '1', body: 'Test', source_url: 'https://example.com/1' }

        comment = described_class.from_hash(hash)

        expect(comment.source_url).to eq('https://example.com/1')
      end

      it 'extracts source-url with hyphen (symbol)' do
        hash = { id: '1', body: 'Test', 'source-url': 'https://example.com/2' }

        comment = described_class.from_hash(hash)

        expect(comment.source_url).to eq('https://example.com/2')
      end

      it 'extracts source-url with hyphen (string)' do
        hash = { id: '1', body: 'Test', 'source-url' => 'https://example.com/3' }

        comment = described_class.from_hash(hash)

        expect(comment.source_url).to eq('https://example.com/3')
      end
    end

    context 'with attributes' do
      it 'extracts attribute_* fields' do
        hash = {
          id: '1',
          body: 'Test',
          attribute_age: '30代',
          attribute_region: '東京'
        }

        comment = described_class.from_hash(hash)

        expect(comment.attributes).to eq({ 'age' => '30代', 'region' => '東京' })
      end

      it 'extracts attribute-* fields' do
        hash = {
          id: '1',
          body: 'Test',
          'attribute-age' => '40代',
          'attribute-region' => '大阪'
        }

        comment = described_class.from_hash(hash)

        expect(comment.attributes).to eq({ 'age' => '40代', 'region' => '大阪' })
      end

      it 'returns nil when no attributes exist' do
        hash = { id: '1', body: 'Test' }

        comment = described_class.from_hash(hash)

        expect(comment.attributes).to be_nil
      end
    end

    context 'with properties' do
      it 'extracts property fields based on property_names' do
        hash = { id: '1', body: 'Test', source: 'twitter', age: 35 }

        comment = described_class.from_hash(hash, property_names: %w[source age])

        expect(comment.properties).to eq({ 'source' => 'twitter', 'age' => 35 })
      end

      it 'returns nil when all property values are nil' do
        hash = { id: '1', body: 'Test' }

        comment = described_class.from_hash(hash, property_names: %w[source age])

        expect(comment.properties).to be_nil
      end

      it 'returns nil when property_names is empty' do
        hash = { id: '1', body: 'Test', source: 'twitter' }

        comment = described_class.from_hash(hash, property_names: [])

        expect(comment.properties).to be_nil
      end
    end
  end

  describe '.from_object' do
    let(:comment_class) do
      Struct.new(:id, :body, :proposal_id, :source_url, :attributes, keyword_init: true)
    end

    it 'normalizes object comments' do
      obj = comment_class.new(id: '1', body: 'Test comment', proposal_id: '123')

      comment = described_class.from_object(obj)

      expect(comment.id).to eq('1')
      expect(comment.body).to eq('Test comment')
      expect(comment.proposal_id).to eq('123')
    end

    it 'extracts attributes from object' do
      obj = comment_class.new(id: '1', body: 'Test', attributes: { 'age' => '30代' })

      comment = described_class.from_object(obj)

      expect(comment.attributes).to eq({ 'age' => '30代' })
    end

    it 'returns nil for empty attributes' do
      obj = comment_class.new(id: '1', body: 'Test', attributes: {})

      comment = described_class.from_object(obj)

      expect(comment.attributes).to be_nil
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      comment = described_class.new(
        id: '1',
        body: 'Test',
        proposal_id: '123',
        source_url: 'https://example.com',
        attributes: { 'age' => '30代' },
        properties: { 'source' => 'twitter' }
      )

      hash = comment.to_h

      expect(hash[:id]).to eq('1')
      expect(hash[:body]).to eq('Test')
      expect(hash[:proposal_id]).to eq('123')
      expect(hash[:source_url]).to eq('https://example.com')
      expect(hash[:attributes]).to eq({ 'age' => '30代' })
      expect(hash[:properties]).to eq({ 'source' => 'twitter' })
    end
  end

  describe '#empty?' do
    it 'returns true when body is nil' do
      comment = described_class.new(id: '1', body: nil)

      expect(comment.empty?).to be true
    end

    it 'returns true when body is whitespace only' do
      comment = described_class.new(id: '1', body: '   ')

      expect(comment.empty?).to be true
    end

    it 'returns false when body has content' do
      comment = described_class.new(id: '1', body: 'Test')

      expect(comment.empty?).to be false
    end
  end
end
