# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:rspec)

RuboCop::RakeTask.new

task default: %i[rspec rubocop]

desc "Checks if commands.md file is up to date"
task :check_command_docs do
  sh "./script/check_command_docs"
end

desc "Updates commands.md file"
task :update_command_docs do
  sh "./script/update_command_docs"
end
