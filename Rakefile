# frozen_string_literal: true

require "appraisal"
require "rake/testtask"
require "bundler/gem_tasks"

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

desc "Run the full Rails compatibility matrix through Appraisal"
task compat: :appraisal

desc "Run the local warm-boot benchmark against the dummy Rails app"
task :benchmark do
  sh "bin/benchmark"
end

task default: :test
