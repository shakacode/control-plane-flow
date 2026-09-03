# frozen_string_literal: true

class TimedCommand
  def self.capture(*command, capture_stderr:, separate_stderr:, timeout_seconds:)
    new(command, capture_stderr, separate_stderr, timeout_seconds).capture
  end

  def initialize(command, capture_stderr, separate_stderr, timeout_seconds)
    raise ArgumentError, "timeout_seconds must be positive" unless timeout_seconds.positive?

    @command = command
    @capture_stderr = capture_stderr
    @separate_stderr = separate_stderr
    @timeout_seconds = timeout_seconds
  end

  def capture
    return capture_separate_streams if @separate_stderr
    return capture_merged_streams if @capture_stderr

    capture_stdout
  end

  private

  def capture_stdout
    Open3.popen2(*@command, pgroup: true) do |stdin, stdout, wait_thread|
      stdin.close
      output_reader = Thread.new { stdout.read }
      wait_for_command(wait_thread)
      { output: output_reader.value, success: wait_thread.value.success? }
    ensure
      output_reader&.join
    end
  end

  def capture_merged_streams
    Open3.popen2e(*@command, pgroup: true) do |stdin, output, wait_thread|
      stdin.close
      output_reader = Thread.new { output.read }
      wait_for_command(wait_thread)
      { output: output_reader.value, success: wait_thread.value.success? }
    ensure
      output_reader&.join
    end
  end

  def capture_separate_streams # rubocop:disable Metrics/MethodLength
    Open3.popen3(*@command, pgroup: true) do |stdin, stdout, stderr, wait_thread|
      stdin.close
      output_reader = Thread.new { stdout.read }
      error_reader = Thread.new { stderr.read }
      wait_for_command(wait_thread)
      {
        output: output_reader.value,
        error_output: error_reader.value,
        success: wait_thread.value.success?
      }
    ensure
      output_reader&.join
      error_reader&.join
    end
  end

  def wait_for_command(wait_thread)
    return if wait_thread.join(@timeout_seconds)

    terminate_process_group(wait_thread)
    raise Shell::CommandTimeout, "Command exceeded the #{@timeout_seconds}-second timeout"
  end

  def terminate_process_group(wait_thread)
    Process.kill("TERM", -wait_thread.pid)
    return if wait_thread.join(1)

    Process.kill("KILL", -wait_thread.pid)
    wait_thread.join
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end
end
