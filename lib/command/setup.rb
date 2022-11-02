# frozen_string_literal: true

module Command
  class Setup < Base
    def call
      ENV["CPL_GVC"] = config.app
      ENV["CPL_CONFIG_PATH"] = config.app_cpln_dir
      ENV["CPL_REVIEW_LOCATION"] = config[:location]
      ENV["CPL_ORG"] = config[:org]

      exec("#{config.script_path}/old_commands/setup.sh", *config.args)
    end
  end
end
