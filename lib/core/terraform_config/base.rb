# frozen_string_literal: true

require_relative "dsl"

module TerraformConfig
  class Base
    include Dsl

    def to_tf
      raise NotImplementedError
    end

    def locals
      {}
    end
  end
end
