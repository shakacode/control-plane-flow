# frozen_string_literal: true

module Command
  class Setup < Base
    def call
      ENV["CPL_GVC"] = config.options[:app]
      ENV["CPL_CONFIG_PATH"] = config.app_cp_dir
      ENV["CPL_REVIEW_LOCATION"] = config.review_apps[:location]
      ENV["CPL_ORG"] = config.review_apps[:org]

      exec("#{config.script_path}/old_commands/setup.sh", *config.args)
    end
  end
end
