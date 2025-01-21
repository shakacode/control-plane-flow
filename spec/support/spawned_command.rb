# frozen_string_literal: true

require "expect"

require_relative "log_helpers"

class SpawnedCommand
  attr_reader :output, :input, :pid

  DEFAULT_TIMEOUT = 120

  def initialize(output, input, pid)
    @output = output
    @input = input
    @pid = pid
  end

  def wait_for(regex, timeout: DEFAULT_TIMEOUT)
    result = nil
    output.expect(regex, timeout) do |matches|
      result = matches&.first
    end

    LogHelpers.write_line_to_log(result)

    raise "Timed out waiting for #{regex.inspect} after #{timeout} seconds" if result.nil?

    result
  end

  def wait_for_prompt
    wait_for(/[$#>]/)
  end

  def type(string)
    input.puts("#{string}\n")
  end

  def kill
    Process.kill("INT", pid)
  end
end
