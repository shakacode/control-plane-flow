# frozen_string_literal: true

module Command
  class Ps < Base
    def call
      case config.args.first
      when nil then show_replicas
      when "start" then start_all
      when "stop" then stop_all
      else abort("ERROR: Unknown ps args")
      end
    end

    private

    def show_replicas
      all_workloads.each do |workload|
        result = cp.workload_get_replicas(workload, location: config[:location])
        result["items"].each { |replica| puts replica } if result
      end
    end

    def stop_all
      all_workloads.each do |workload|
        cp.workload_set_suspend(workload, true)
        progress.puts "#{workload} stopped"
      end
    end

    def start_all
      all_workloads.reverse_each do |workload|
        cp.workload_set_suspend(workload, false)
        progress.puts "#{workload} started"
      end
    end

    def all_workloads
      config[:app_workloads] + config[:additional_workloads]
    end
  end
end
