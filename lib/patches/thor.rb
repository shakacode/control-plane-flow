# frozen_string_literal: true

class Thor
  # Verified against Thor 1.5.0. The parser regression in spec/cpflow_spec.rb
  # guards the private @switches/no_or_skip? contract used here.
  module ExplicitStringSkipOption
    private

    def no_or_skip?(switch)
      option = @switches&.[](switch)
      return false if option&.string?

      super
    end
  end

  Options.prepend(ExplicitStringSkipOption)

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
