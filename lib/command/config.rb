# frozen_string_literal: true

module Command
  class Config < Base
    def call
      pp Controlplane.new(config, org: 1)
    end
  end
end
