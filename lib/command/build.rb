# frozen_string_literal: true

module Command
  class Build < Base
    def call
      dockerfile = config.current[:dockerfile] || "Dockerfile"
      dockerfile = "#{config.app_cpln_dir}/#{dockerfile}"
      progress.puts "- Building dockerfile: #{dockerfile}"

      cp.image_build(latest_image_next, dockerfile: dockerfile)
    end
  end
end
