# frozen_string_literal: true

class Shell
  class << self
    attr_reader :tmp_stderr, :verbose
  end

  def self.shell
    @shell ||= Thor::Shell::Color.new
  end

  def self.stderr
    @stderr ||= $stderr
  end

  def self.use_tmp_stderr
    @tmp_stderr = Tempfile.create

    yield

    @tmp_stderr.close
    @tmp_stderr = nil
  end

  def self.write_to_tmp_stderr(message)
    tmp_stderr.write(message)
  end

  def self.read_from_tmp_stderr
    tmp_stderr.rewind
    tmp_stderr.read.strip
  end

  def self.color(message, color_key)
    shell.set_color(message, color_key)
  end

  def self.confirm(message)
    shell.yes?("#{message} (y/N)")
  end

  def self.warn(message)
    stderr.puts(color("WARNING: #{message}", :yellow))
  end

  def self.warn_deprecated(message)
    stderr.puts(color("DEPRECATED: #{message}", :yellow))
  end

  def self.abort(message)
    Kernel.abort(color("ERROR: #{message}", :red))
  end

  def self.verbose_mode(verbose)
    @verbose = verbose
  end

  def self.debug(prefix, message, sensitive_data_pattern: nil)
    return unless verbose

    filtered_message = hide_sensitive_data(message, sensitive_data_pattern)
    stderr.puts("\n[#{color(prefix, :red)}] #{filtered_message}")
  end

  def self.should_hide_output?
    tmp_stderr && !verbose
  end

  #
  # Hide sensitive data based on the passed pattern
  #
  # @param [String] message
  #   The message to get processed.
  # @param [Regexp, nil] pattern
  #   The regular expression to be used. If not provided, no filter gets applied.
  #
  # @return [String]
  #   Filtered message.
  #
  # @example
  #   hide_sensitive_data("--token abcd", /(?<=--token )(\S+)/)
  def self.hide_sensitive_data(message, pattern = nil)
    return message unless pattern.is_a?(Regexp)

    message.gsub(pattern, "XXXXXXX")
  end
end
