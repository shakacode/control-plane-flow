# frozen_string_literal: true

module Command
  class Config < Base
    def call
      puts "-- Options"
      puts config.options.to_yaml[4..]
      puts

      puts "-- Current config (app: #{config.app})"
      puts config.app ? config.current.to_yaml[4..] : "Please specify app to get app config"
      puts
    end
  end
end
