# frozen_string_literal: true

class MinimalConfig
  attr_reader :options

  def initialize(args)
    @options = args[:options]
  end
end
