# frozen_string_literal: true

require "spec_helper"

describe CommandHelpers do
  describe "command logging" do
    it "redacts a sensitive value embedded in a command argument" do
      sensitive_value = "opaque-sensitive-value"
      sensitive_pattern = /#{Regexp.escape(sensitive_value)}/

      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)
        allow(Cpflow::Cli).to receive(:start)

        run_cpflow_command(
          "run", "-a", "test-app", "--", "echo #{sensitive_value}",
          sensitive_data_pattern: sensitive_pattern
        )

        contents = File.read(log_file.path)
        expect(contents).not_to include(sensitive_value)
        expect(contents).to include("echo XXXXXXX")
      end
    end

    it "forwards redaction through the raising command helper" do
      sensitive_value = "opaque-sensitive-value"
      sensitive_pattern = /#{Regexp.escape(sensitive_value)}/
      command_args = ["run", "-a", "test-app", "--", "echo #{sensitive_value}"]

      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)
        allow(Cpflow::Cli).to receive(:start)

        run_cpflow_command!(*command_args, sensitive_data_pattern: sensitive_pattern)

        expect(Cpflow::Cli).to have_received(:start).with(command_args)
        expect(File.read(log_file.path)).not_to include(sensitive_value)
      end
    end

    it "redacts a failing bang command from its log and raised result" do
      sensitive_value = "opaque-sensitive-value"
      sensitive_pattern = /#{Regexp.escape(sensitive_value)}/

      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)
        allow(Cpflow::Cli).to receive(:start) do
          $stdout.puts("stdout #{sensitive_value}")
          warn("stderr #{sensitive_value}")
          exit(ExitCode::ERROR_DEFAULT)
        end

        run_command = lambda do
          run_cpflow_command!(
            "run", "-a", "test-app", "--", "echo #{sensitive_value}",
            sensitive_data_pattern: sensitive_pattern
          )
        end
        redacted_error = raise_error(RuntimeError) do |error|
          expect(error.message).not_to include(sensitive_value)
          expect(JSON.parse(error.message)).to include(
            "status" => ExitCode::ERROR_DEFAULT,
            "stdout" => "stdout XXXXXXX\n",
            "stderr" => "stderr XXXXXXX\n"
          )
        end
        expect { run_command.call }.to redacted_error

        contents = File.read(log_file.path)
        expect(contents).not_to include(sensitive_value)
        expect(contents).to include("echo XXXXXXX", "stdout XXXXXXX", "stderr XXXXXXX")
      end
    end
  end

  describe "DUMMY_TEST_APP_NAME_PATTERN" do
    it "matches every app name the dummy app helpers can generate" do
      names = [
        dummy_test_app,
        dummy_test_app("nothing"),
        dummy_test_app("valid-pre-deletion-hook"),
        dummy_test_app("image-retention", "1"),
        dummy_test_app_prefix,
        dummy_test_app_prefix("info-nothing-missing")
      ]

      expect(names).to all(match(described_class::DUMMY_TEST_APP_NAME_PATTERN))
    end

    it "does not match permanent org fixtures or non-test apps" do
      names = %w[dummy-test-upstream dummy-test production-app not-dummy-test-bbbb]

      expect(names).to all(satisfy { |name| !described_class::DUMMY_TEST_APP_NAME_PATTERN.match?(name) })
    end
  end

  describe "registering apps for suite cleanup" do
    # `apps_to_delete` is process-wide state consumed by `after(:suite)`, so
    # these examples must not leave their fake app names behind.
    around do |example|
      registered = described_class.apps_to_delete.dup
      example.run
      described_class.apps_to_delete.replace(registered)
    end

    before do
      allow(Cpflow::Cli).to receive(:start)
    end

    it "registers an app created by setup-app even when the command fails" do
      allow(Cpflow::Cli).to receive(:start).and_raise(SystemExit.new(1))
      app = dummy_test_app("valid-pre-deletion-hook")

      result = run_cpflow_command("setup-app", "-a", app)

      expect(result[:status]).to eq(1)
      expect(described_class.apps_to_delete).to include(app)
    end

    it "registers an app created by apply-template" do
      app = dummy_test_app("stale-app")

      run_cpflow_command!("apply-template", "app", "-a", app)

      expect(described_class.apps_to_delete).to include(app)
    end

    it "registers an app created through a spawned command" do
      app = dummy_test_app("spawned")
      allow(PTY).to receive(:spawn)

      spawn_cpflow_command("setup-app", "-a", app)

      expect(described_class.apps_to_delete).to include(app)
    end

    it "does not register apps for commands that cannot create one" do
      app = dummy_test_app("nothing")

      run_cpflow_command("exists", "-a", app)

      expect(described_class.apps_to_delete).not_to include(app)
    end

    it "does not register names outside the dummy app naming boundary" do
      run_cpflow_command("setup-app", "-a", "dummy-test-upstream")

      expect(described_class.apps_to_delete).not_to include("dummy-test-upstream")
    end
  end

  describe "names with a multi-segment suffix" do
    it "stays inside the cleanup boundary, so generation and validation cannot drift" do
      name = "#{CommandHelpers::DUMMY_TEST_APP_PREFIX}-default-ab12-release-a"

      expect(CommandHelpers::DUMMY_TEST_APP_NAME_PATTERN).to match(name)
    end

    it "still excludes the permanent upstream fixture" do
      expect(CommandHelpers::DUMMY_TEST_APP_NAME_PATTERN)
        .not_to match("#{CommandHelpers::DUMMY_TEST_APP_PREFIX}-upstream")
    end
  end
end
