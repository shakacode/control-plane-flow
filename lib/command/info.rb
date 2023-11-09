# frozen_string_literal: true

module Command
  class Info < Base # rubocop:disable Metrics/ClassLength
    NAME = "info"
    OPTIONS = [
      app_option
    ].freeze
    DESCRIPTION = "Displays the diff between defined/available apps/workloads (apps equal GVCs)"
    LONG_DESCRIPTION = <<~DESC
      - Displays the diff between defined/available apps/workloads (apps equal GVCs)
      - Apps that are defined but not available are displayed in red
      - Apps that are available but not defined are displayed in green
      - Apps that are both defined and available are displayed in white
      - The diff is based on what's defined in the `.controlplane/controlplane.yml` file
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Shows diff for all apps in all orgs (based on `.controlplane/controlplane.yml`).
      cpl info

      # Shows diff for all apps in a specific org.
      cpl info -o $ORG_NAME

      # Shows diff for a specific app.
      cpl info -a $APP_NAME
      ```
    EX
    WITH_INFO_HEADER = false

    def call
      @missing_apps_workloads = {}
      @missing_apps_starting_with = {}

      if config.app && !config.current[:match_if_app_name_starts_with]
        single_app_info
      else
        multiple_apps_info
      end
    end

    private

    def app_matches?(app, app_name, app_options)
      app == app_name.to_s || (app_options[:match_if_app_name_starts_with] && app.start_with?(app_name.to_s))
    end

    def find_app_options(app)
      @app_options ||= {}
      @app_options[app] ||= config.apps.find do |app_name, app_options|
                              app_matches?(app, app_name, app_options)
                            end&.last
    end

    def find_workloads(app)
      app_options = find_app_options(app)
      return [] if app_options.nil?

      (app_options[:app_workloads] + app_options[:additional_workloads] + [app_options[:one_off_workload]]).uniq
    end

    def fetch_workloads(app)
      cp.fetch_workloads(app)["items"].map { |workload| workload["name"] }
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
        result.select { |app, _| app_matches?(app, config.app, config.current) }
      else
        result.reject { |app, _| find_app_options(app).nil? }
      end
    end

    def orgs # rubocop:disable Metrics/MethodLength
      result = []

      if config.org
        result.push(config.org)
      else
        config.apps.each do |app_name, app_options|
          next if config.app && !app_matches?(config.app, app_name, app_options)

          org = app_options[:cpln_org]
          result.push(org) if org && !result.include?(org)
        end
      end

      result.sort
    end

    def apps(org)
      result = []

      config.apps.each do |app_name, app_options|
        next if config.app && !app_matches?(config.app, app_name, app_options)

        app_org = app_options[:cpln_org]
        result.push(app_name.to_s) if app_org == org
      end

      result += @app_workloads.keys.map(&:to_s)
      result.uniq.sort
    end

    def any_app_starts_with?(app)
      @app_workloads.keys.find { |app_name| app_matches?(app_name, app, config.apps[app.to_sym]) }
    end

    def check_any_app_starts_with(app)
      if any_app_starts_with?(app)
        false
      else
        @missing_apps_starting_with[app] ||= ["gvc"]

        puts "  - #{Shell.color("Any app starting with '#{app}'", :red)}"
        true
      end
    end

    def add_to_missing_workloads(app, workload)
      if config.should_app_start_with?(app)
        @missing_apps_starting_with[app] ||= []
        @missing_apps_starting_with[app].push(workload)
      else
        @missing_apps_workloads[app] ||= []
        @missing_apps_workloads[app].push(workload)
      end
    end

    def print_app(app, org)
      if config.should_app_start_with?(app)
        check_any_app_starts_with(app)
      elsif cp.fetch_gvc(app, org).nil?
        @missing_apps_workloads[app] = ["gvc"]

        puts "  - #{Shell.color(app, :red)}"
        true
      else
        puts "  - #{app}"
        true
      end
    end

    def print_workload(app, workload)
      if @defined_workloads.include?(workload) && !@available_workloads.include?(workload)
        add_to_missing_workloads(app, workload)

        puts "    - #{Shell.color(workload, :red)}"
      elsif !@defined_workloads.include?(workload) && @available_workloads.include?(workload)
        puts "    - #{Shell.color(workload, :green)}"
      else
        puts "    - #{workload}"
      end
    end

    def print_missing_apps_workloads
      return if @missing_apps_workloads.empty?

      puts "\nSome apps/workloads are missing. Please create them with:"

      @missing_apps_workloads.each do |app, workloads|
        if workloads.include?("gvc")
          puts "  - `cpl setup-app -a #{app}`"
        else
          puts "  - `cpl apply-template #{workloads.join(' ')} -a #{app}`"
        end
      end
    end

    def print_missing_apps_starting_with
      return if @missing_apps_starting_with.empty?

      puts "\nThere are no apps starting with some names. If you wish to create any, do so with " \
           "(replace 'whatever' with whatever suffix you want):"

      @missing_apps_starting_with.each do |app, _workloads|
        app_with_suffix = "#{app}#{app.end_with?('-') ? '' : '-'}whatever"
        puts "  - `cpl setup-app -a #{app_with_suffix}`"
      end
    end

    def single_app_info
      puts "#{Shell.color(config.org, :blue)}:"

      print_app(config.app, config.org)

      @defined_workloads = find_workloads(config.app)
      @available_workloads = fetch_workloads(config.app)

      workloads = (@defined_workloads + @available_workloads).uniq.sort
      workloads.each do |workload|
        print_workload(config.app, workload)
      end

      print_missing_apps_workloads
    end

    def multiple_apps_info # rubocop:disable Metrics/MethodLength
      orgs.each do |org|
        puts "#{Shell.color(org, :blue)}:"

        @app_workloads = fetch_app_workloads(org)

        apps(org).each do |app|
          next unless print_app(app, org)

          @defined_workloads = find_workloads(app)
          @available_workloads = @app_workloads[app] || []

          workloads = (@defined_workloads + @available_workloads).uniq.sort
          workloads.each do |workload|
            print_workload(app, workload)
          end
        end

        puts
      end

      print_missing_apps_workloads
      print_missing_apps_starting_with
    end
  end
end
