# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  command_name "spawn"
  enable_coverage :branch

  at_fork.call(Process.pid)
end
