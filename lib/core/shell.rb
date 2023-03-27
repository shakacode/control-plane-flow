# frozen_string_literal: true

class Shell
  class << self
    attr_reader :tmp_stderr
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
    shell.yes?("#{message} (y/n)")
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
end
