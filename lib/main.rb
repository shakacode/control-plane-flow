# frozen_string_literal: true

Dir[
  "#{__dir__}/core/*.rb",
  "#{__dir__}/command/*.rb"
].each { require(_1) }

config = Config.new
commands = Command::Base.all_commands

commands[config.cmd] ? commands[config.cmd].new(config).call : abort("ERROR: Unknown command '#{config.cmd}'")
