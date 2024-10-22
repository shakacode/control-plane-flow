# frozen_string_literal: true

module TerraformConfig
  class Provider < Base
    attr_reader :name, :options

    def initialize(name, **options)
      super()

      @name = name
      @options = options
    end

    def to_tf
      block :provider, name do
        options.each do |option, value|
          argument option, value
        end
      end
    end
  end
end
