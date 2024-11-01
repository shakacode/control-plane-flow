# frozen_string_literal: true

class Array
  def crush
    crushed = map { |el| el.respond_to?(:crush) ? el.crush : el }.compact
    crushed unless crushed.empty?
  end
end
