# frozen_string_literal: true

module Command
  class Generator < Thor::Group
    include Thor::Actions

    def copy_files
      directory("generator_templates", ".controlplane", verbose: ENV.fetch("RAILS_ENV", nil) != "test")
    end

    def self.source_root
      File.expand_path("../", __dir__)
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
      cpl generate
      ```
    EX
    WITH_INFO_HEADER = false

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
