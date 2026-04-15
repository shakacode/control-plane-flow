# frozen_string_literal: true

module Command
  class Generator < Thor::Group
    include Thor::Actions

    DEFAULT_RUBY_VERSION = "3.1.2"

    def copy_files
      directory("generator_templates", ".controlplane", verbose: ENV.fetch("HIDE_COMMAND_OUTPUT", nil) != "true")
      substitute_template_variables(".controlplane")
      make_shell_scripts_executable(".controlplane")
    end

    def self.source_root
      Cpflow.root_path.join("lib")
    end

    private

    def substitute_template_variables(root_path)
      Dir.glob(File.join(root_path, "**/*")).each do |path|
        next unless File.file?(path)

        contents = File.read(path)
        updated_contents = template_variables.reduce(contents) do |memo, (placeholder, value)|
          memo.gsub(placeholder, value)
        end

        next if updated_contents == contents

        File.write(path, updated_contents)
      end
    end

    def template_variables
      {
        "__RUBY_VERSION__" => inferred_ruby_version
      }
    end

    def inferred_ruby_version
      ruby_version_from_ruby_version_file ||
        ruby_version_from_tool_versions ||
        ruby_version_from_gemfile ||
        DEFAULT_RUBY_VERSION
    end

    def ruby_version_from_ruby_version_file
      return unless File.file?(".ruby-version")

      parse_ruby_version(File.read(".ruby-version"))
    end

    def ruby_version_from_tool_versions
      return unless File.file?(".tool-versions")

      ruby_line = File.readlines(".tool-versions", chomp: true).find { |line| line.match?(/^\s*ruby\s+/) }
      return unless ruby_line

      parse_ruby_version(ruby_line.sub(/^\s*ruby\s+/, ""))
    end

    def ruby_version_from_gemfile
      return unless File.file?("Gemfile")

      ruby_line = File.readlines("Gemfile", chomp: true).find { |line| line.match?(/^\s*ruby\s+/) }
      return unless ruby_line

      parse_ruby_version(ruby_line.sub(/^\s*ruby\s+/, ""))
    end

    def parse_ruby_version(source)
      normalized_source = source.strip.sub(/\Aruby-/, "")
      normalized_source[/\d+\.\d+(?:\.\d+)?/]
    end

    def make_shell_scripts_executable(root_path)
      Dir.glob(File.join(root_path, "**/*.sh")).each do |path|
        next unless File.file?(path)

        FileUtils.chmod(0o755, path)
      end
    end
  end

  class Generate < Base
    NAME = "generate"
    DESCRIPTION = "Creates base Control Plane config and template files"
    LONG_DESCRIPTION = <<~DESC
      Creates base Control Plane config and template files
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Creates .controlplane directory with Control Plane config and other templates
      cpflow generate
      ```
    EX
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze

    def call
      if controlplane_directory_exists?
        Shell.warn("The directory '.controlplane' already exists!")
        return
      end

      Generator.start
    end

    private

    def controlplane_directory_exists?
      Dir.exist? ".controlplane"
    end
  end
end
