# frozen_string_literal: true

module Command
  module Terraform
    class Generate < Base
      SUBCOMMAND_NAME = "terraform"
      NAME = "generate"
      OPTIONS = [
        app_option,
        dir_option
      ].freeze
      DESCRIPTION = "Generates terraform configuration files"
      LONG_DESCRIPTION = <<~DESC
        - Generates terraform configuration files based on `controlplane.yml` and `templates/` config
      DESC
      WITH_INFO_HEADER = false

      def call
        generate_common_configs
        generate_app_configs
      end

      private

      def generate_common_configs
        cpln_provider = TerraformConfig::RequiredProvider.new(
          "cpln",
          source: "controlplane-com/cpln",
          version: "~> 1.0"
        )

        File.write(terraform_dir.join("providers.tf"), cpln_provider.to_tf)
      end

      def generate_app_configs
        Array(config.app || config.apps.keys).each do |app|
          config.instance_variable_set(:@app, app)
          generate_app_config
        end
      end

      def generate_app_config
        terraform_app_dir = recreate_terraform_app_dir

        templates.each do |template|
          generator = TerraformConfig::Generator.new(config: config, template: template)

          # TODO: Delete line below after all template kinds are supported
          next unless %w[gvc identity secret].include?(template["kind"])

          File.write(terraform_app_dir.join(generator.filename), generator.tf_config.to_tf, mode: "a+")
        end
      end

      def recreate_terraform_app_dir
        full_path = terraform_dir.join(config.app)

        unless File.expand_path(full_path).include?(Cpflow.root_path.to_s)
          Shell.abort("Directory to save terraform configuration files cannot be outside of current directory")
        end

        FileUtils.rm_rf(full_path)
        FileUtils.mkdir_p(full_path)

        full_path
      end

      def templates
        parser = TemplateParser.new(self)
        template_files = Dir["#{parser.template_dir}/*.yml"]

        if template_files.empty?
          Shell.warn("No templates found in #{parser.template_dir}")
          return []
        end

        parser.parse(template_files)
      rescue StandardError => e
        Shell.warn("Error parsing templates: #{e.message}")
        []
      end

      def terraform_dir
        @terraform_dir ||= begin
          full_path = config.options.fetch(:dir, Cpflow.root_path.join("terraform"))
          Pathname.new(full_path).tap do |path|
            FileUtils.mkdir_p(path)
          rescue StandardError => e
            Shell.abort("Invalid directory: #{e.message}")
          end
        end
      end
    end
  end
end
