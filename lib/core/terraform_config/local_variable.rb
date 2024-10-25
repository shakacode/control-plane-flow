# frozen_string_literal: true

module TerraformConfig
  class LocalVariable < Base
    attr_reader :variables

    def initialize(**variables)
      super()

      @variables = variables
    end

    def to_tf
      block :locals do
        variables.each do |var, value|
          argument var, value
        end
      end
    end
  end
end
