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

  # Helper to read saved status file
  def read_status_file
    JSON.parse(File.read(File.join(output_dir, 'status.json')), symbolize_names: true)
  end

  describe '#initialize' do
    context 'when status file does not exist' do
      it 'initializes with empty completed jobs' do
        expect(status.all_completed_jobs).to eq([])
      end
    end

    context 'when status file exists' do
      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'status.json'), {
          status: 'completed',
          completed_jobs: [ { step: 'extraction', completed: '2024-01-01T00:00:00Z', duration: 1.0, params: {}, token_usage: 0 } ]
        }.to_json)
      end

      it 'loads existing completed jobs' do
        expect(status.all_completed_jobs.size).to eq(1)
        expect(status.all_completed_jobs.first.step).to eq('extraction')
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
      content = read_status_file
      expect(content[:status]).to eq('initialized')
    end
  end

  describe '#start_pipeline' do
    let(:plan) do
      [
        Broadlistening::PlanStep.new(step: :extraction, run: true, reason: 'no trace of previous run'),
        Broadlistening::PlanStep.new(step: :embedding, run: false, reason: 'nothing changed')
      ]
    end

    it 'saves status as running to file' do
      status.start_pipeline(plan)
      content = read_status_file
      expect(content[:status]).to eq('running')
    end

    it 'stores the plan in file' do
      status.start_pipeline(plan)
      content = read_status_file
      expect(content[:plan].size).to eq(2)
    end

    it 'sets start_time in file' do
      status.start_pipeline(plan)
      content = read_status_file
      expect(content[:start_time]).to be_a(String)
    end

    it 'sets lock_until in file' do
      status.start_pipeline(plan)
      content = read_status_file
      expect(content[:lock_until]).to be_a(String)
    end

    it 'saves to file' do
      status.start_pipeline(plan)
      expect(File.exist?(File.join(output_dir, 'status.json'))).to be true
    end

    it 'resets completed jobs' do
      status.start_pipeline(plan)
      expect(status.all_completed_jobs).to eq([])
    end
  end

  describe '#start_step' do
    it 'sets current_job in file' do
      status.start_step(:extraction)
      content = read_status_file
      expect(content[:current_job]).to eq('extraction')
    end

    it 'sets current_job_started in file' do
      status.start_step(:extraction)
      content = read_status_file
      expect(content[:current_job_started]).to be_a(String)
    end

    it 'updates lock_until in file' do
      status.start_step(:extraction)
      content = read_status_file
      expect(content[:lock_until]).to be_a(String)
    end
  end

  describe '#complete_step' do
    let(:params) { { model: 'gpt-4o-mini' } }

    before do
      status.start_step(:extraction)
    end

    it 'adds job to all_completed_jobs' do
      status.complete_step(:extraction, params: params, duration: 10.5)
      expect(status.all_completed_jobs.size).to eq(1)
      expect(status.all_completed_jobs.first.step).to eq('extraction')
    end

    it 'records duration' do
      status.complete_step(:extraction, params: params, duration: 10.5)
      expect(status.all_completed_jobs.first.duration).to eq(10.5)
    end

    it 'records params' do
      status.complete_step(:extraction, params: params, duration: 10.5)
      expect(status.all_completed_jobs.first.params[:model]).to eq('gpt-4o-mini')
    end

    it 'hashes long string params' do
      long_prompt = 'a' * 200
      status.complete_step(:extraction, params: { prompt: long_prompt }, duration: 10.5)
      expect(status.all_completed_jobs.first.params[:prompt]).to eq(Digest::SHA256.hexdigest(long_prompt))
    end

    it 'clears current_job in file' do
      status.complete_step(:extraction, params: params, duration: 10.5)
      content = read_status_file
      expect(content[:current_job]).to be_nil
    end

    it 'saves completed job to file' do
      status.complete_step(:extraction, params: params, duration: 10.5)
      content = read_status_file
      expect(content[:completed_jobs].size).to eq(1)
      expect(content[:completed_jobs].first[:step]).to eq('extraction')
    end
  end

  describe '#complete_pipeline' do
    before do
      status.start_pipeline([ Broadlistening::PlanStep.new(step: :extraction, run: true, reason: 'test') ])
      status.start_step(:extraction)
      status.complete_step(:extraction, params: {}, duration: 1.0)
    end

    it 'sets status to completed in file' do
      status.complete_pipeline
      content = read_status_file
      expect(content[:status]).to eq('completed')
    end

    it 'sets end_time in file' do
      status.complete_pipeline
      content = read_status_file
      expect(content[:end_time]).to be_a(String)
    end
  end

  describe '#error_pipeline' do
    let(:error) { StandardError.new('test error') }

    it 'sets status to error in file' do
      status.error_pipeline(error)
      content = read_status_file
      expect(content[:status]).to eq('error')
    end

    it 'records error message in file' do
      status.error_pipeline(error)
      content = read_status_file
      expect(content[:error]).to eq('StandardError: test error')
    end

    it 'sets end_time in file' do
      status.error_pipeline(error)
      content = read_status_file
      expect(content[:end_time]).to be_a(String)
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
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'status.json'), {
          status: 'running',
          lock_until: (Time.now - 60).iso8601
        }.to_json)
      end

      subject(:status) { described_class.new(output_dir) }

      it 'returns false' do
        expect(status.locked?).to be false
      end
    end

    context 'when status is running and lock is active' do
      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'status.json'), {
          status: 'running',
          lock_until: (Time.now + 300).iso8601
        }.to_json)
      end

      subject(:status) { described_class.new(output_dir) }

      it 'returns true' do
        expect(status.locked?).to be true
      end
    end
  end

  describe '#all_completed_jobs' do
    before do
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, 'status.json'), {
        status: 'completed',
        completed_jobs: [ { step: 'extraction', completed: '2024-01-01T00:00:00Z', duration: 1.0, params: {}, token_usage: 0 } ],
        previously_completed_jobs: [ { step: 'embedding', completed: '2024-01-01T00:00:00Z', duration: 2.0, params: {}, token_usage: 0 } ]
      }.to_json)
    end

    subject(:status) { described_class.new(output_dir) }

    it 'returns combined completed_jobs and previously_completed_jobs' do
      jobs = status.all_completed_jobs
      expect(jobs.size).to eq(2)
    end

    it 'returns CompletedJob objects' do
      jobs = status.all_completed_jobs
      expect(jobs.first).to be_a(Broadlistening::CompletedJob)
      expect(jobs.first.step).to eq('extraction')
    end

    it 'returns jobs in order (current first, then previous)' do
      jobs = status.all_completed_jobs
      expect(jobs.map(&:step)).to eq(%w[extraction embedding])
    end
  end
end
