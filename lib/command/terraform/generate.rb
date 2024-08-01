# frozen_string_literal: true

module Command
  module Terraform
    class Generate < Base
      SUBCOMMAND_NAME = "terraform"
      NAME = "generate"
      DESCRIPTION = "Generates terraform configuration files"
      LONG_DESCRIPTION = <<~DESC
        - Generates terraform configuration files based on `controlplane.yml` and `templates/` config
      DESC
      WITH_INFO_HEADER = false
      VALIDATIONS = [].freeze

      def call
        # TODO: Implement
      end
    end
  end
end
