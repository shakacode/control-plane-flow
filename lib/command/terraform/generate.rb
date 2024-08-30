# frozen_string_literal: true

module Command
  module Terraform
    class Generate < Base
      SUBCOMMAND_NAME = "terraform"
      NAME = "generate"
      OPTIONS = [
        app_option(required: true)
      ].freeze
      DESCRIPTION = "Generates terraform configuration files"
      LONG_DESCRIPTION = <<~DESC
        - Generates terraform configuration files based on `controlplane.yml` and `templates/` config
      DESC
      WITH_INFO_HEADER = false

      def call
        File.write(terraform_dir.join("providers.tf"), cpln_provider.to_tf)

        templates.each do |template|
          generator = TerraformConfig::Generator.new(config: config, template: template)

          # TODO: Delete line below after all template kinds are supported
          next unless %w[gvc identity].include?(template["kind"])

          File.write(terraform_dir.join(generator.filename), generator.tf_config.to_tf, mode: "a+")
        end
      end

      private

      def cpln_provider
        TerraformConfig::RequiredProvider.new("cpln", source: "controlplane-com/cpln", version: "~> 1.0")
      end

      def templates
        parser = TemplateParser.new(self)
        parser.parse(Dir["#{parser.template_dir}/*.yml"])
      end

      def terraform_dir
        @terraform_dir ||= Cpflow.root_path.join("terraform").tap do |path|
          FileUtils.rm_rf(path)
          FileUtils.mkdir_p(path)
        end
      end
    end
  end
end
