# frozen_string_literal: true

module Command
  class Env < Base
    def call
      cp.gvc_get.dig("spec", "env").map do |prop|
        # NOTE: atm no special chars handling, consider adding if needed
        puts "#{prop['name']}=#{prop['value']}"
      end
    end
  end
end
