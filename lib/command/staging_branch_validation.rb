# frozen_string_literal: true

module Command
  module StagingBranchValidation
    private

    def staging_branch
      branch = config.options[:staging_branch].to_s.strip
      return nil if branch.empty?

      unless valid_staging_branch?(branch)
        Shell.abort(
          "Invalid --staging-branch value: #{branch.inspect}. " \
          "Use a valid git branch name containing only alphanumerics, dots, slashes, underscores, hyphens, and @."
        )
      end

      branch
    end

    def valid_staging_branch?(branch)
      return false unless branch.match?(%r{\A[a-zA-Z0-9._/@-]+\z})

      valid_git_branch_shape?(branch) && valid_git_branch_components?(branch)
    end

    def valid_git_branch_shape?(branch)
      return false if branch.start_with?("-", "/", ".")
      return false if branch.end_with?("/", ".")
      return false if branch.include?("@{")

      !branch.include?("..")
    end

    def valid_git_branch_components?(branch)
      branch.split("/").none? do |component|
        component.empty? || component.start_with?(".") || component.end_with?(".lock")
      end
    end
  end
end
