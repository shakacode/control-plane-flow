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
        File.write(terraform_dir.join("providers.tf"), cpln_provider.to_tf)
      end

      private

      def cpln_provider
        ::TerraformConfig::RequiredProvider.new("cpln", source: "controlplane-com/cpln", version: "~> 1.0")
      end

      def terraform_dir
        @terraform_dir ||= Cpflow.root_path.join("terraform").tap do |path|
          FileUtils.mkdir_p(path)
        end
      end
    end
  end
end
