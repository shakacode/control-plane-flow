# frozen_string_literal: true

module TerraformConfig
  class RequiredProvider < Base
    attr_reader :name, :org, :options

    def initialize(name:, org:, **options)
      super()

      @name = name
      @org = org
      @options = options
    end

    def to_tf
      block :terraform do
        block :cloud do
          argument :organization, org
        end

        block :required_providers do
          argument name, options
        end
      end
    end
  end
end
