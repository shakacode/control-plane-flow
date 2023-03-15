# frozen_string_literal: true

class Shell
  def self.shell
    @shell ||= Thor::Shell::Color.new
  end

  def self.stderr
    @stderr ||= $stderr
  end

  def self.color(message, color_key)
    shell.set_color(message, color_key)
  end

  def self.confirm(message)
    shell.yes?("#{message} (y/n)")
  end

  def self.warn(message)
    stderr.puts(color("WARNING: #{message}\n", :yellow))
  end

  def self.warn_deprecated(message)
    stderr.puts(color("DEPRECATED: #{message}\n", :yellow))
  end

  def self.abort(message)
    Kernel.abort(color("ERROR: #{message}\n", :red))
  end
end
