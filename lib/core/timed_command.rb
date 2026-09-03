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
    @deadline = monotonic_time + @timeout_seconds
    @command_cleaned_up = false
    return capture_separate_streams if @separate_stderr
    return capture_merged_streams if @capture_stderr

    capture_stdout
  end

  private

  def capture_stdout # rubocop:disable Metrics/MethodLength
    completed = false
    Open3.popen2(*@command, pgroup: true) do |stdin, stdout, wait_thread|
      stdin.close
      output_reader = Thread.new { stdout.read }
      wait_for_command(wait_thread, output_reader)
      completed = true
      { output: output_reader.value, success: wait_thread.value.success? }
    ensure
      cleanup_unfinished_command(wait_thread, output_reader) unless completed || @command_cleaned_up
      output_reader&.join
    end
  end

  def capture_merged_streams # rubocop:disable Metrics/MethodLength
    completed = false
    Open3.popen2e(*@command, pgroup: true) do |stdin, output, wait_thread|
      stdin.close
      output_reader = Thread.new { output.read }
      wait_for_command(wait_thread, output_reader)
      completed = true
      { output: output_reader.value, success: wait_thread.value.success? }
    ensure
      cleanup_unfinished_command(wait_thread, output_reader) unless completed || @command_cleaned_up
      output_reader&.join
    end
  end

  def capture_separate_streams # rubocop:disable Metrics/MethodLength
    completed = false
    Open3.popen3(*@command, pgroup: true) do |stdin, stdout, stderr, wait_thread|
      stdin.close
      output_reader = Thread.new { stdout.read }
      error_reader = Thread.new { stderr.read }
      wait_for_command(wait_thread, output_reader, error_reader)
      completed = true
      {
        output: output_reader.value,
        error_output: error_reader.value,
        success: wait_thread.value.success?
      }
    ensure
      cleanup_unfinished_command(wait_thread, output_reader, error_reader) unless completed || @command_cleaned_up
      output_reader&.join
      error_reader&.join
    end
  end

  def wait_for_command(wait_thread, *output_readers)
    observed_threads = [wait_thread, *output_readers]
    return if observed_threads.all? { |thread| thread.join(remaining_timeout) }

    terminate_process_group(wait_thread)
    output_readers.each(&:kill)
    output_readers.each(&:join)
    @command_cleaned_up = true
    raise Shell::CommandTimeout, "Command exceeded the #{@timeout_seconds}-second timeout"
  end

  def remaining_timeout
    [@deadline - monotonic_time, 0].max
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def terminate_process_group(wait_thread)
    Process.kill("TERM", -wait_thread.pid)
    wait_thread.join(1)

    Process.kill("KILL", -wait_thread.pid)
    wait_thread.join
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def cleanup_unfinished_command(wait_thread, *output_readers)
    return unless wait_thread

    terminate_process_group(wait_thread)
    output_readers.compact.each(&:kill)
  end
end
