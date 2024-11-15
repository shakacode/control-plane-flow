# frozen_string_literal: true

module Command
  module Terraform
    class Base < Base
      private

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
