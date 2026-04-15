# frozen_string_literal: true

module Command
  module GeneratorHelpers
    private

    def substitute_template_variables(file_paths, replacements = template_variables)
      Array(file_paths).each do |path|
        next unless File.file?(path)

        contents = File.read(path)
        updated_contents = replacements.reduce(contents) do |memo, (placeholder, value)|
          memo.gsub(placeholder, value)
        end

        next if updated_contents == contents

        File.write(path, updated_contents)
      end
    end

    def make_shell_scripts_executable(file_paths)
      Array(file_paths).each do |path|
        next unless File.file?(path) && File.extname(path) == ".sh"

        FileUtils.chmod(0o755, path)
      end
    end
  end
end
