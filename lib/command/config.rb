# frozen_string_literal: true

module Command
  class Config < Base
    NAME = "config"
    OPTIONS = [
      app_option
    ].freeze
    DESCRIPTION = "Displays current configs (global and app-specific)"
    LONG_DESCRIPTION = <<~DESC
      - Displays current configs (global and app-specific)
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Shows the global config.
      cpl config

      # Shows both global and app-specific configs.
      cpl config -a $APP_NAME
      ```
    EX

    def call
      puts "-- Options"
      puts config.options.to_hash.to_yaml[4..]
      puts

      puts "-- Current config (app: #{config.app})"
      puts config.app ? config.current.to_yaml[4..] : "Please specify app to get app config"
      puts
    end
  end
end
