# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"

options_by_key_name = Command::Base.all_options_by_key_name
non_boolean_options_by_key_name = options_by_key_name
                                  .reject { |_, option| option[:params][:type] == :boolean }

describe Cpflow do
  it "has a version number" do
    expect(Cpflow::VERSION).not_to be_nil
  end

  it "loads without development-only debug dependencies" do
    script = <<~RUBY
      module Kernel
        alias_method :cpflow_original_require, :require

        def require(path)
          raise LoadError, "debug must not be required at runtime" if path == "debug"

          cpflow_original_require(path)
        end
      end

      require "cpflow"
      puts Cpflow::VERSION
      puts Command::UpdateGithubActions::LONG_DESCRIPTION.length
    RUBY

    child_env = ENV.each_key.grep(/\ABUNDLE/).to_h { |key| [key, nil] }
    child_env["RUBYLIB"] = nil
    child_env["RUBYOPT"] = nil

    stdout, stderr, status = Open3.capture3(
      child_env,
      RbConfig.ruby,
      "-I",
      File.expand_path("../lib", __dir__),
      "-e",
      script
    )

    expect(status).to be_success, stderr
    stdout_lines = stdout.lines.map(&:chomp)
    expect(stdout_lines).to include(Cpflow::VERSION)
    expect(Integer(stdout_lines.fetch(1))).to be_positive
  end

  it "loads with a US-ASCII external encoding" do
    child_env = ENV.each_key.grep(/\ABUNDLE/).to_h { |key| [key, nil] }
    child_env["LC_ALL"] = "C"
    child_env["LANG"] = "C"
    child_env["RUBYLIB"] = nil
    child_env["RUBYOPT"] = nil

    stdout, stderr, status = Open3.capture3(
      child_env,
      RbConfig.ruby,
      "-I",
      File.expand_path("../lib", __dir__),
      "-e",
      "require \"cpflow\"; puts Cpflow::VERSION"
    )

    expect(status).to be_success, stderr
    expect(stdout).to include(Cpflow::VERSION)
  end

  non_boolean_options_by_key_name.each do |option_key_name, option|
    it "raises error if no value is provided for '#{option_key_name}' option" do
      result = run_cpflow_command("test", option_key_name)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("No value provided for option --#{option[:name].to_s.tr('_', '-')}")
    end
  end

  describe ".validate_options!" do
    it "validates regexes against the current command options only" do
      command_options = [
        {
          name: :mode,
          params: {
            valid_regex: /^(preview|apply)$/
          }
        }
      ]

      expect do
        Cpflow::Cli.validate_options!({ "mode" => "preview" }, command_options: command_options)
      end.not_to raise_error
    end
  end

  it "handles subcommands correctly" do
    result = run_cpflow_command("--help")

    expect(result[:status]).to eq(0)

    # Temporary solution, will be fixed with https://github.com/rails/thor/issues/742
    basename = Cpflow::Cli.send(:basename)

    Cpflow::Cli.subcommand_names.each do |subcommand|
      expect(result[:stdout]).to include("#{basename} #{subcommand}")

      subcommand_result = run_cpflow_command(subcommand, "--help")

      expect(subcommand_result[:status]).to eq(0)
      expect(subcommand_result[:stdout]).to include("#{basename} #{subcommand} help [COMMAND]")
    end
  end

  it "skips startup checks for top-level help" do
    result = run_cpflow_command("--help")

    expect(result[:status]).to eq(0)
    expect(Cpflow::Cli).not_to have_received(:check_cpln_version)
    expect(Cpflow::Cli).not_to have_received(:check_cpflow_version)
  end

  it "skips startup checks for local-only GitHub flow commands" do
    %w[
      generate-github-actions
      update-github-actions
      github-flow-readiness
      ai-github-flow-prompt
    ].each do |command_name|
      expect(Cpflow::Cli.send(:requires_startup_checks?, [command_name])).to be(false)
    end
  end

  it "reminds gem installers to update generated GitHub Actions wrappers" do
    spec = Gem::Specification.load(File.expand_path("../cpflow.gemspec", __dir__))

    expect(spec.post_install_message).to include("cpflow update-github-actions")
    expect(spec.post_install_message).to include("https://shakacode.com/control-plane-flow/docs/ci-automation/#updating-generated-github-actions-after-gem-updates")
  end
end
