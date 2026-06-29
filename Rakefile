# frozen_string_literal: true

require "appraisal"
require "rake/testtask"
require "bundler/gem_tasks"
require_relative "lib/rails_doctor/package_audit"

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

desc "Run Standard Ruby"
task :lint do
  sh "bundle exec standardrb"
end

desc "Run the full Rails compatibility matrix through Appraisal"
task compat: :appraisal

desc "Run the local warm-boot benchmark against the dummy Rails app"
task :benchmark do
  sh "bin/benchmark"
end

namespace :package do
  desc "Build the gem and verify the packaged Rails command surface"
  task :verify do
    RailsDoctor::PackageAudit.verify!(root: __dir__)
  end
end

desc "Run the default production-readiness checks"
task verify: %i[test lint package:verify]

task default: :verify
