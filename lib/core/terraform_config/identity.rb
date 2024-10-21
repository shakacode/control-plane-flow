# frozen_string_literal: true

module TerraformConfig
  class Identity < Base
    attr_reader :gvc, :name, :description, :tags

    def initialize(gvc:, name:, description: nil, tags: nil)
      super()

      @gvc = gvc
      @name = name
      @description = description
      @tags = tags
    end

    def to_tf
      block :resource, :cpln_identity, name do
        argument :gvc, gvc

        argument :name, name
        argument :description, description, optional: true

        argument :tags, tags, optional: true
      end
    end
  end
end
