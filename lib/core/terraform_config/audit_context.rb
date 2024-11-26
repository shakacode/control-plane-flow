# frozen_string_literal: true

module TerraformConfig
  class AuditContext < Base
    attr_reader :name, :description, :tags

    def initialize(name:, description: nil, tags: nil)
      super()

      @name = name
      @description = description
      @tags = tags
    end

    def to_tf
      block :resource, :cpln_audit_context, name do
        argument :name, name
        argument :description, description, optional: true
        argument :tags, tags, optional: true
      end
    end
  end
end
