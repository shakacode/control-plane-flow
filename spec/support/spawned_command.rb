# frozen_string_literal: true

require "expect"
require "timeout"

require_relative "log_helpers"

class SpawnedCommand
  attr_reader :output, :input, :pid

  DEFAULT_TIMEOUT = 120
  PROCESS_EXIT_GRACE_SECONDS = 5
  PROCESS_TERM_GRACE_SECONDS = 2
  PROCESS_KILL_GRACE_SECONDS = 1

  def initialize(output, input, pid, sensitive_data_pattern: nil)
    @output = output
    @input = input
    @pid = pid
    @sensitive_data_pattern = sensitive_data_pattern
  end

  def wait_for(regex, timeout: DEFAULT_TIMEOUT)
    result = nil
    output.expect(regex, timeout) do |matches|
      result = matches&.first
    end

    redacted_result = result && Shell.hide_sensitive_data(result, @sensitive_data_pattern)
    LogHelpers.write_line_to_log(redacted_result)

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

  def wait
    return if wait_with_timeout(PROCESS_EXIT_GRACE_SECONDS)

    signal("TERM")
    return if wait_with_timeout(PROCESS_TERM_GRACE_SECONDS)

    signal("KILL")
    return if wait_with_timeout(PROCESS_KILL_GRACE_SECONDS)

    Process.detach(pid)
  rescue Errno::ECHILD
    nil
  end

  private

  def wait_with_timeout(seconds)
    Timeout.timeout(seconds) { Process.wait(pid) }
    true
  rescue Timeout::Error
    false
  rescue Errno::ECHILD
    true
  end

  def signal(name)
    Process.kill(name, pid)
  rescue Errno::ESRCH
    nil
  end
end
