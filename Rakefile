# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

# Load RuboCop if available
begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new(:audit)
rescue LoadError
  # RuboCop not available, define a simple task
  task :audit do
    puts 'RuboCop not installed. Run `bundle install` to install development dependencies.'
  end
end

# Default task
task default: [:audit]
