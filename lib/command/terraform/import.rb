# frozen_string_literal: true

module Command
  module Terraform
    class Import < Base
      SUBCOMMAND_NAME = "terraform"
      NAME = "import"
      OPTIONS = [
        app_option,
        dir_option
      ].freeze
      DESCRIPTION = "Imports terraform resources"
      LONG_DESCRIPTION = <<~DESC
        - Imports terraform resources from the generated configuration files.
      DESC
      WITH_INFO_HEADER = false

      def call
        Array(config.app || config.apps.keys).each do |app|
          config.instance_variable_set(:@app, app.to_s)

          Dir.chdir(terraform_app_dir) do
            run_terraform_init

            resources.each do |resource|
              run_terraform_import(resource[:address], resource[:id])
            end
          end
        end
      end

      private

      def run_terraform_init
        result = Shell.cmd("terraform init", capture_stderr: true)

        if result[:success]
          Shell.info(result[:output])
        else
          Shell.abort("Failed to initialize terraform - #{result[:output]}")
        end
      end

      def run_terraform_import(address, id)
        result = Shell.cmd("terraform import #{address} #{id}", capture_stderr: true)
        Shell.info(result[:output])
      end

      def resources
        tf_configs.filter_map do |tf_config|
          next unless tf_config.importable?

          { address: tf_config.reference, id: resource_id(tf_config) }
        end
      end

      def tf_configs
        templates.flat_map do |template|
          TerraformConfig::Generator.new(config: config, template: template).tf_configs.values
        end
      end

      def resource_id(tf_config)
        case tf_config
        when TerraformConfig::Gvc, TerraformConfig::Policy, TerraformConfig::Secret
          tf_config.name
        else
          "#{config.app}:#{tf_config.name}"
        end
      end

      def terraform_app_dir
        terraform_dir.join(config.app)
      end
    end
  end
end
