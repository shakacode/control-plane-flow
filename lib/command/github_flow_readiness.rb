# frozen_string_literal: true

module Command
  class GithubFlowReadiness < Base
    NAME = "github-flow-readiness"
    DESCRIPTION = "Checks whether the current repo is ready for the Control Plane GitHub flow rollout"
    LONG_DESCRIPTION = <<~DESC
      Checks the current repository for common rollout blockers before adding the Control Plane GitHub flow:
      - Rails runtime scaffold present
      - modern Ruby and Bundler toolchain
      - installable exact-pinned direct gem and npm package versions
      - production Dockerfile presence and SQLite production hints
    DESC
    EXAMPLES = <<~EX
      ```sh
      # Checks the current repo for common rollout blockers
      cpflow github-flow-readiness
      ```
    EX
    WITH_INFO_HEADER = false
    VALIDATIONS = [].freeze
    REQUIRES_STARTUP_CHECKS = false

    def call
      service = GithubFlowReadinessService.new

      service.results.each do |result|
        Shell.info("[#{result.status.to_s.upcase}] #{result.message}")
      end

      Shell.info("")
      Shell.info(service.summary)

      exit(ExitCode::ERROR_DEFAULT) if service.blockers?
    end
  end
end
