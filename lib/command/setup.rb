# frozen_string_literal: true

module Command
  class Setup < Base
    def call
      config.args.each do |template|
        filename = "#{config.app_cpln_dir}/templates/#{template}.yml"
        abort("ERROR: Can't find template for '#{template}' at #{filename}") unless File.exist?(filename)

        apply_template(filename)
        progress.puts(template)
      end
    end

    private

    def apply_template(filename)
      data = File.read(filename)
                 .gsub("APP_GVC", config.app)
                 .gsub("APP_LOCATION", config[:default_location])
                 .gsub("APP_ORG", config[:cpln_org])
                 .gsub("APP_IMAGE", latest_image)

      cp.apply(YAML.safe_load(data))
    end
  end
end
