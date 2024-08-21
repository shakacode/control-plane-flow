# frozen_string_literal: true

module TerraformConfig
  class RequiredProvider < Base
    attr_reader :name, :options

    def initialize(name, **options)
      super()

      @name = name
      @options = options
    end

    def to_tf
      block :terraform do
        block :required_providers do
          argument name, options
        end
      end
    end
  end
end
