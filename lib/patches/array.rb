# frozen_string_literal: true

class Array
  def crush
    crushed = map(&:crush).compact
    crushed unless crushed.empty?
  end
end
