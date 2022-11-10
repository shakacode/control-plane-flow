# frozen_string_literal: true

require "benchmark"
require "json"
require "net/http"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"

(Dir["#{__dir__}/**/*.rb"] - [__FILE__]).sort.each { require(_1) }

config = Config.new
commands = Command::Base.all_commands

abort("ERROR: Unknown command '#{config.cmd}'") unless commands[config.cmd]

# nice Ctrl+C
trap "INT" do
  puts
  exit(1)
end

commands[config.cmd].new(config).call
