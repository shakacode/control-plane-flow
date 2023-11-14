# frozen_string_literal: true

module Command
  class Env < Base
    NAME = "env"
    OPTIONS = [
      app_option(required: true)
    ].freeze
    DESCRIPTION = "Displays app-specific environment variables"
    LONG_DESCRIPTION = <<~DESC
      - Displays app-specific environment variables
    DESC
    WITH_INFO_HEADER = false

    def call
      cp.fetch_gvc!.dig("spec", "env").map do |prop|
        # NOTE: atm no special chars handling, consider adding if needed
        puts "#{prop['name']}=#{prop['value']}"
      end
    end
  end
end
