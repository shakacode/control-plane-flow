# frozen_string_literal: true

module Command
  class Info < Base
    NAME = "info"
    OPTIONS = [
      org_option,
      app_option
    ].freeze
    DESCRIPTION = "Displays a list of available workloads for all apps or a specific app in an org (apps equal GVCs)"
    LONG_DESCRIPTION = <<~HEREDOC
      - Displays a list of available workloads for all apps or a specific app in an org (apps equal GVCs)
    HEREDOC
    EXAMPLES = <<~HEREDOC
      ```sh
      # Shows available workloads for all apps.
      cpl info

      # Shows available workloads for a specific app.
      cpl info -a $APP_NAME

      # Shows available workloads for all apps in a different org.
      cpl info -o $ORG_NAME
      ```
    HEREDOC

    def call
      ensure_org!

      gvcs = config.app ? [config.app] : cp.fetch_gvcs["items"].map { |gvc| gvc["name"] }
      gvcs.each do |gvc|
        puts Shell.color(gvc, :blue)

        workloads = cp.fetch_workloads(gvc)["items"].map { |workload| workload["name"] }
        workloads.each do |workload|
          puts "  #{workload}"
        end
      end
    end

    private

    def ensure_org!
      return if config.org

      Shell.abort("Please specify an org, either through the '-o' flag " \
                  "or the 'default_cpln_org' key in 'controlplane.yml'.")
    end
  end
end
