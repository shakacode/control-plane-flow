# frozen_string_literal: true

module Command
  class Base
    attr_reader :config

    def initialize(config)
      @config = config
    end

    def self.all_commands
      Dir["#{__dir__}/*.rb"].each_with_object({}) do |file, result|
        filename = File.basename(file, ".rb")
        classname = File.read(file).match(/^\s+class (\w+) < Base$/)&.captures&.first
        result[filename.to_sym] = Object.const_get("::Command::#{classname}") if classname
      end
    end

    def wait_for(title)
      progress.print "- Waiting for #{title}"
      until yield
        progress.print(".")
        sleep(1)
      end
      progress.puts
    end

    # NOTE: use simplified variant atm, as shelljoin do different escaping
    # TODO: most probably need better logic for escaping various quotes
    def args_join(args)
      args.join(" ")
    end

    def progress
      $stderr
    end

    def cp
      @cp ||= Controlplane.new(config)
    end
  end
end
