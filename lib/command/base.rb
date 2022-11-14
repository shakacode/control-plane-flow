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
        classname = File.read(file).match(/^\s+class (\w+) < Base($| .*$)/)&.captures&.first
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

    def latest_image
      @latest_image ||= cp.image_query["items"]
                          .filter_map { _1["name"] if _1["name"].start_with?("#{config.app}:") }
                          .max_by(&method(:extract_image_number)) || "#{config.app}:0"
    end

    def latest_image_next
      @latest_image_next ||= "#{latest_image.split(':').first}:#{extract_image_number(latest_image) + 1}"
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

    private

    def extract_image_number(image_name)
      image_name.match(/:(\d+)/)&.captures&.first.to_i
    end
  end
end
