# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"
require "optparse"
require "pathname"
require "tempfile"
require "yaml"

(Dir["#{__dir__}/**/*.rb"] - [__FILE__]).sort.each { require(_1) }

config = Config.new
commands = Command::Base.all_commands

deprecated = {
  build: "build-image",
  promote: "promote-image",
  runner: "run:detached"
}[config.cmd]

if deprecated
  logger = $stderr
  logger.puts("DEPRECATED: command '#{config.cmd_untranslated}' is deprecated, use '#{deprecated}' instead\n")
  command = deprecated.tr(":-", "_").to_sym
end

command ||= config.cmd

abort("ERROR: Unknown command '#{config.cmd_untranslated}'") unless commands[command]

# nice Ctrl+C
trap "INT" do
  puts
  exit(1)
end

commands[config.cmd].new(config).call
