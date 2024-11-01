# frozen_string_literal: true

module TerraformConfig
  class LocalVariable < Base
    VARIABLE_NAME_REGEX = /\A[a-zA-Z][a-zA-Z0-9_]*\z/.freeze

    attr_reader :variables

    def initialize(**variables)
      super()

      @variables = variables
      validate_variables!
    end

    def to_tf
      block :locals do
        variables.each do |var, value|
          argument var, value
        end
      end
    end

    private

    def validate_variables!
      raise ArgumentError, "Variables cannot be empty" if variables.empty?
    end
  end
end
