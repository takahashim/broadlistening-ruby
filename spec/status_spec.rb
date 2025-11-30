# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe Broadlistening::Status do
  let(:output_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(output_dir)
  end

  subject(:status) { described_class.new(output_dir) }

  describe '#initialize' do
    context 'when status file does not exist' do
      it 'initializes with default values' do
        expect(status.data[:status]).to eq('initialized')
        expect(status.data[:completed_jobs]).to eq([])
        expect(status.data[:previously_completed_jobs]).to eq([])
      end
    end

    context 'when status file exists' do
      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'status.json'), {
          status: 'completed',
          completed_jobs: [ { step: 'extraction', completed: '2024-01-01T00:00:00Z' } ]
        }.to_json)
      end

      it 'loads existing status' do
        expect(status.data[:status]).to eq('completed')
        expect(status.data[:completed_jobs].size).to eq(1)
      end
    end
  end

  describe '#save' do
    it 'creates output directory if needed' do
      new_dir = File.join(output_dir, 'nested', 'dir')
      new_status = described_class.new(new_dir)
      new_status.save
      expect(File.exist?(File.join(new_dir, 'status.json'))).to be true
    end

    it 'writes status to file as JSON' do
      status.save
      content = JSON.parse(File.read(File.join(output_dir, 'status.json')))
      expect(content['status']).to eq('initialized')
    end
  end

  describe '#start_pipeline' do
    let(:plan) do
      [
        { step: :extraction, run: true, reason: 'no trace of previous run' },
        { step: :embedding, run: false, reason: 'nothing changed' }
      ]
    end

    it 'updates status to running' do
      status.start_pipeline(plan)
      expect(status.data[:status]).to eq('running')
    end

    it 'stores the plan' do
      status.start_pipeline(plan)
      expect(status.data[:plan].size).to eq(2)
    end

    it 'sets start_time' do
      status.start_pipeline(plan)
      expect(status.data[:start_time]).to be_a(String)
    end

    it 'sets lock_until' do
      status.start_pipeline(plan)
      expect(status.data[:lock_until]).to be_a(String)
    end

    it 'saves to file' do
      status.start_pipeline(plan)
      expect(File.exist?(File.join(output_dir, 'status.json'))).to be true
    end
  end

  describe '#start_step' do
    it 'sets current_job' do
      status.start_step(:extraction)
      expect(status.data[:current_job]).to eq('extraction')
    end

    it 'sets current_job_started' do
      status.start_step(:extraction)
      expect(status.data[:current_job_started]).to be_a(String)
    end

    it 'updates lock_until' do
      status.start_step(:extraction)
      expect(status.data[:lock_until]).to be_a(String)
    end
  end

  describe '#complete_step' do
    let(:params) { { model: 'gpt-4o-mini' } }

    before do
      status.start_step(:extraction)
    end

    it 'adds job to completed_jobs' do
      status.complete_step(:extraction, params: params, duration: 10.5)
      expect(status.data[:completed_jobs].size).to eq(1)
      expect(status.data[:completed_jobs].first[:step]).to eq('extraction')
    end

    it 'records duration' do
      status.complete_step(:extraction, params: params, duration: 10.5)
      expect(status.data[:completed_jobs].first[:duration]).to eq(10.5)
    end

    it 'records params' do
      status.complete_step(:extraction, params: params, duration: 10.5)
      expect(status.data[:completed_jobs].first[:params][:model]).to eq('gpt-4o-mini')
    end

    it 'hashes long string params' do
      long_prompt = 'a' * 200
      status.complete_step(:extraction, params: { prompt: long_prompt }, duration: 10.5)
      expect(status.data[:completed_jobs].first[:params][:prompt]).to eq(Digest::SHA256.hexdigest(long_prompt))
    end

    it 'clears current_job' do
      status.complete_step(:extraction, params: params, duration: 10.5)
      expect(status.data[:current_job]).to be_nil
    end
  end

  describe '#complete_pipeline' do
    before do
      status.start_pipeline([ { step: :extraction, run: true, reason: 'test' } ])
      status.start_step(:extraction)
      status.complete_step(:extraction, params: {}, duration: 1.0)
    end

    it 'sets status to completed' do
      status.complete_pipeline
      expect(status.data[:status]).to eq('completed')
    end

    it 'sets end_time' do
      status.complete_pipeline
      expect(status.data[:end_time]).to be_a(String)
    end
  end

  describe '#error_pipeline' do
    let(:error) { StandardError.new('test error') }

    it 'sets status to error' do
      status.error_pipeline(error)
      expect(status.data[:status]).to eq('error')
    end

    it 'records error message' do
      status.error_pipeline(error)
      expect(status.data[:error]).to eq('StandardError: test error')
    end

    it 'sets end_time' do
      status.error_pipeline(error)
      expect(status.data[:end_time]).to be_a(String)
    end
  end

  describe '#locked?' do
    context 'when status is not running' do
      it 'returns false' do
        expect(status.locked?).to be false
      end
    end

    context 'when status is running but lock expired' do
      before do
        status.data[:status] = 'running'
        status.data[:lock_until] = (Time.now - 60).iso8601
      end

      it 'returns false' do
        expect(status.locked?).to be false
      end
    end

    context 'when status is running and lock is active' do
      before do
        status.data[:status] = 'running'
        status.data[:lock_until] = (Time.now + 300).iso8601
      end

      it 'returns true' do
        expect(status.locked?).to be true
      end
    end
  end

  describe '#previous_completed_jobs' do
    it 'returns combined completed_jobs and previously_completed_jobs' do
      status.data[:completed_jobs] = [ { step: 'extraction' } ]
      status.data[:previously_completed_jobs] = [ { step: 'embedding' } ]

      jobs = status.previous_completed_jobs
      expect(jobs.size).to eq(2)
    end
  end
end
