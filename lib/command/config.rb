# frozen_string_literal: true

module Command
  class Config < Base
    def call
      pp Controlplane.new(config)
    end
  end
end
