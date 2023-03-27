# frozen_string_literal: true

module Command
  class Info < Base
    NAME = "info"
    OPTIONS = [
      org_option,
      app_option
    ].freeze
    DESCRIPTION = "Displays a list of available workloads for all apps or a specific app " \
                  "in all orgs or a specific org (apps equal GVCs)"
    LONG_DESCRIPTION = <<~DESC
      - Displays a list of available workloads for all apps or a specific app in all orgs or a specific org (apps equal GVCs)
      - Only displays apps/workloads that match what's defined in the `.controlplane/controlplane.yml` file
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Shows available workloads for all apps in all orgs.
      cpl info

      # Shows available workloads for all apps in a specific org.
      cpl info -o $ORG_NAME

      # Shows available workloads for a specific app.
      cpl info -a $APP_NAME
      ```
    EX

    def call
      if config.app && !config.current[:match_if_app_name_starts_with]
        single_app_info
      else
        multiple_apps_info
      end
    end

    private

    def check_if_app_matches(app, app_name, app_options)
      app == app_name.to_s || (app_options[:match_if_app_name_starts_with] && app.start_with?(app_name.to_s))
    end

    def find_app_options(app)
      @app_options ||= {}
      @app_options[app] ||= config.apps.find do |app_name, app_options|
                              check_if_app_matches(app, app_name, app_options)
                            end&.last
    end

    def filter_workloads(app, workloads)
      app_options = find_app_options(app)
      return [] if app_options.nil?

      workloads.filter do |workload|
        app_options[:app_workloads].include?(workload) ||
          app_options[:additional_workloads].include?(workload) ||
          app_options[:one_off_workload] == workload
      end.sort
    end

    def orgs
      result = []

      if config.options[:org]
        result.push(config.options[:org])
      else
        config.apps.each do |_app, app_options|
          org = app_options[:cpln_org] || app_options[:org]
          result.push(org) unless result.include?(org)
        end
      end

      result
    end

    def fetch_app_workloads(org) # rubocop:disable Metrics/MethodLength
      result = {}

      workloads = cp.fetch_workloads_by_org(org)["items"]
      workloads.each do |workload|
        app = workload["links"].find { |link| link["rel"] == "gvc" }["href"].split("/").last

        result[app] ||= []
        result[app].push(workload["name"])
      end

      if config.app
        result.select! { |app, _| check_if_app_matches(app, config.app, config.current) }
      else
        result.reject! { |app, _| find_app_options(app).nil? }
      end

      result.sort.to_h
    end

    def single_app_info
      puts "#{Shell.color(config.org, :blue)}:"
      puts "  #{config.app}:"

      workloads = cp.fetch_workloads["items"].map { |workload| workload["name"] }
      workloads = filter_workloads(config.app, workloads)
      return puts "    No available workloads." if workloads.empty?

      workloads.each do |workload|
        puts "    - #{workload}"
      end
    end

    def multiple_apps_info # rubocop:disable Metrics/MethodLength
      orgs.each do |org|
        puts "#{Shell.color(org, :blue)}:"

        app_workloads = fetch_app_workloads(org)
        next puts "  No available apps." if app_workloads.empty?

        app_workloads.each do |app, workloads|
          puts "  #{app}:"

          workloads = filter_workloads(app, workloads)
          next puts "    No available workloads." if workloads.empty?

          workloads.each do |workload|
            puts "    - #{workload}"
          end
        end
      end
    end
  end
end
