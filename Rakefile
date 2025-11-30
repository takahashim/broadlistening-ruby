# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

RSpec::Core::RakeTask.new("spec:compatibility") do |t|
  t.pattern = "spec/compatibility/**/*_spec.rb"
end

namespace :compatibility do
  desc "Validate Kouchou-AI Python output structure"
  task :validate_python do
    require "bundler/setup"
    require "broadlistening"
    require "json"

    python_path = File.expand_path(
      "../server/broadlistening/pipeline/outputs/example-hierarchical-polis/hierarchical_result.json",
      __dir__
    )

    unless File.exist?(python_path)
      puts "Error: Python output not found at: #{python_path}"
      exit 1
    end

    output = JSON.parse(File.read(python_path))
    errors = Broadlistening::Compatibility.validate_output(output)

    if errors.empty?
      puts "Valid: #{python_path}"
      puts ""
      puts "Stats:"
      puts "  Arguments: #{output['arguments'].size}"
      puts "  Clusters: #{output['clusters'].size}"
      puts "  Levels: #{output['clusters'].map { |c| c['level'] }.uniq.sort.join(', ')}"
      puts "  Has overview: #{!output['overview'].to_s.strip.empty?}"
    else
      puts "Invalid: #{python_path}"
      errors.each { |e| puts "  - #{e}" }
      exit 1
    end
  end

  desc "Compare Python and Ruby outputs"
  task :compare, [ :python_file, :ruby_file ] do |_t, args|
    require "bundler/setup"
    require "broadlistening"

    python_file = args[:python_file]
    ruby_file = args[:ruby_file]

    unless python_file && ruby_file
      puts "Usage: rake compatibility:compare[python_output.json,ruby_output.json]"
      exit 1
    end

    [ python_file, ruby_file ].each do |file|
      unless File.exist?(file)
        puts "Error: File not found: #{file}"
        exit 1
      end
    end

    report = Broadlistening::Compatibility.compare_outputs(
      python_output: python_file,
      ruby_output: ruby_file
    )

    puts report.summary
    exit(report.compatible? ? 0 : 1)
  end
end

task default: :spec
