# frozen_string_literal: true

module LogHelpers
  module_function

  LOG_FILE = ENV.fetch("SPEC_LOG_FILE", "spec.log")

  COMMAND_SEPARATOR = "#" * 100
  SECTION_SEPARATOR = "-" * 100

  def write_command_to_log(cmd, sensitive_data_pattern: nil)
    File.open(LOG_FILE, "a") do |file|
      file.puts(COMMAND_SEPARATOR)
      file.puts(Shell.hide_sensitive_data(cmd, sensitive_data_pattern))
    end
  end

  def write_command_result_to_log(result, sensitive_data_pattern: nil) # rubocop:disable Metrics/MethodLength
    result = redact_command_result(result, sensitive_data_pattern: sensitive_data_pattern)

    File.open(LOG_FILE, "a") do |file|
      file.puts(SECTION_SEPARATOR)
      file.puts("STATUS: #{result[:status]}")
      file.puts(SECTION_SEPARATOR)
      file.puts("STDERR:")
      file.puts(SECTION_SEPARATOR)
      file.puts(result[:stderr])
      file.puts(SECTION_SEPARATOR)
      file.puts("STDOUT:")
      file.puts(SECTION_SEPARATOR)
      file.puts(result[:stdout])
    end
  end

  def redact_command_result(result, sensitive_data_pattern: nil)
    result.merge(
      stderr: Shell.hide_sensitive_data(result[:stderr], sensitive_data_pattern),
      stdout: Shell.hide_sensitive_data(result[:stdout], sensitive_data_pattern)
    )
  end

  def write_section_separator_to_log
    File.open(LOG_FILE, "a") do |file|
      file.puts(SECTION_SEPARATOR)
    end
  end

  def write_line_to_log(line)
    File.open(LOG_FILE, "a") do |file|
      file.puts(line)
    end
  end
end
