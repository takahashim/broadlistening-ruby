# frozen_string_literal: true

require_relative "lib/broadlistening/version"

Gem::Specification.new do |spec|
  spec.name = "broadlistening"
  spec.version = Broadlistening::VERSION
  spec.authors = [ "takahashim" ]
  spec.email = [ "takahashimm@gmail.com" ]

  spec.summary = "Broadlistening pipeline for opinion analysis"
  spec.description = "A Ruby implementation of the Broadlistening pipeline for clustering and analyzing public comments using LLM"
  spec.homepage = "https://github.com/takahashim/broadlistening-ruby"
  spec.license = "AGPL-3.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/takahashim/broadlistening-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/takahashim/broadlistening-ruby/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = [ "lib" ]

  # Runtime dependencies
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "csv", ">= 3.0"
  spec.add_dependency "numo-narray", "~> 0.9"
  spec.add_dependency "parallel", "~> 1.20"
  spec.add_dependency "rice", "~> 4.6.0"
  spec.add_dependency "ruby-openai", "~> 7.0"
  spec.add_dependency "umappp", "~> 0.2"
  spec.add_dependency "json_schemer", "~> 2.0"
end
