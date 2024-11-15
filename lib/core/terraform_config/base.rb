# frozen_string_literal: true

require_relative "dsl"

module TerraformConfig
  class Base
    include Dsl

    def importable?
      false
    end

    def reference
      raise NotImplementedError if importable?
    end

    def to_tf
      raise NotImplementedError
    end

    def locals
      {}
    end
  end
end
