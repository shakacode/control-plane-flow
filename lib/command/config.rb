# frozen_string_literal: true

module Command
  class Config < Base
    NAME = "config"
    OPTIONS = [
      app_option
    ].freeze
    DESCRIPTION = "Displays config for each app or a specific app"
    LONG_DESCRIPTION = <<~DESC
      - Displays config for each app or a specific app
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Shows the config for each app.
      cpflow config

      # Shows the config for a specific app.
      cpflow config -a $APP_NAME
      ```
    EX

    def call # rubocop:disable Metrics/MethodLength
      if config.app
        puts "#{Shell.color("Current config (app '#{config.app}')", :blue)}:"
        puts pretty_print(config.current)
        puts
      else
        config.apps.each do |app_name, app_options|
          puts "#{Shell.color("Config for app '#{app_name}'", :blue)}:"
          puts pretty_print(app_options)
          puts
        end
      end
    end

    private

    def pretty_print(hash)
      hash.transform_keys(&:to_s)
          .to_yaml(indentation: 2)[4..]
          # Adds an indentation of 2 to the beginning of each line
          .gsub(/^(\s*)/, "  \\1")
          # Adds an indentation of 2 before the '-' in array items
          .gsub(/^(\s*)-\s/, "\\1  - ")
    end
  end
end
