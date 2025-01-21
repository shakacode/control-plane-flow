# frozen_string_literal: true

class Thor
  # Fix for https://github.com/erikhuda/thor/issues/398
  # Copied from https://github.com/rails/thor/issues/398#issuecomment-622988390
  module Shell
    class Basic
      def print_wrapped(message, options = {})
        indent = (options[:indent] || 0).to_i
        if indent.zero?
          stdout.puts(message)
        else
          message.each_line do |message_line|
            stdout.print(" " * indent)
            stdout.puts(message_line.chomp)
          end
        end
      end
    end
  end

  # Fix for https://github.com/rails/thor/issues/742
  def self.basename
    @package_name || super
  end
end
