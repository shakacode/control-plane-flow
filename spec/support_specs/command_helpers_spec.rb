# frozen_string_literal: true

require "spec_helper"

describe CommandHelpers do
  describe "command logging" do
    it "redacts values passed through sensitive command options by default" do
      sensitive_value = "opaque-upstream-token"

      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)
        allow(Cpflow::Cli).to receive(:start)

        run_cpflow_command(
          "promote-app-from-upstream", "-a", "test-app", "--upstream-token", sensitive_value
        )

        contents = File.read(log_file.path)
        expect(contents).not_to include(sensitive_value)
        expect(contents).to include("--upstream-token XXXXXXX")
      end
    end

    it "prefers complete sensitive option values over overlapping supplied patterns" do
      sensitive_value = "opaque-upstream-token"

      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)
        allow(Cpflow::Cli).to receive(:start)

        run_cpflow_command(
          "promote-app-from-upstream", "-a", "test-app", "--upstream-token", sensitive_value,
          sensitive_data_pattern: /opaque/
        )

        contents = File.read(log_file.path)
        expect(contents).to include("--upstream-token XXXXXXX")
        expect(contents).not_to include(sensitive_value, "XXXXXXX-upstream-token")
      end
    end

    it "redacts Thor's underscored sensitive option spelling in separate and assigned forms" do
      first_sensitive_value = "opaque-upstream-token-one"
      second_sensitive_value = "opaque-upstream-token-two"

      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)
        allow(Cpflow::Cli).to receive(:start)

        run_cpflow_command(
          "copy-image-from-upstream", "-a", "test-app", "--upstream_token", first_sensitive_value
        )
        run_cpflow_command(
          "copy-image-from-upstream", "-a", "test-app", "--upstream_token=#{second_sensitive_value}"
        )

        contents = File.read(log_file.path)
        expect(contents).to include("--upstream_token XXXXXXX", "--upstream_token=XXXXXXX")
        expect(contents).not_to include(first_sensitive_value, second_sensitive_value)
      end
    end

    it "redacts Thor's attached numeric short-option spelling" do
      sensitive_value = "123456"

      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)
        allow(Cpflow::Cli).to receive(:start)

        run_cpflow_command("copy-image-from-upstream", "-a", "test-app", "-t#{sensitive_value}")

        contents = File.read(log_file.path)
        expect(contents).to include("-tXXXXXXX")
        expect(contents).not_to include(sensitive_value)
      end
    end

    it "redacts the signless token value Thor parses from a signed attached short option" do
      sensitive_value = "123456"

      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)
        allow(Cpflow::Cli).to receive(:start) do
          $stdout.puts("stdout #{sensitive_value}")
          warn("stderr #{sensitive_value}")
        end

        run_cpflow_command("copy-image-from-upstream", "-a", "test-app", "-t+#{sensitive_value}")

        contents = File.read(log_file.path)
        expect(contents).to include("-t+XXXXXXX", "stdout XXXXXXX", "stderr XXXXXXX")
        expect(contents).not_to include(sensitive_value)
      end
    end

    it "does not treat unrelated attached t-prefixed arguments as tokens" do
      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)
        allow(Cpflow::Cli).to receive(:start)

        run_cpflow_command("run", "-a", "test-app", "--", "echo", "-to", "output")

        expect(File.read(log_file.path)).to include("run -a test-app -- echo -to output")
      end
    end

    it "redacts sensitive option values from spawned command logs" do
      sensitive_value = "opaque-upstream-token"

      Tempfile.create("cpflow-command-log") do |log_file|
        stub_const("LogHelpers::LOG_FILE", log_file.path)
        allow(PTY).to receive(:spawn)

        spawn_cpflow_command(
          "copy-image-from-upstream", "-a", "test-app", "--upstream-token", sensitive_value,
          wait_for_process: false
        )

        contents = File.read(log_file.path)
        expect(contents).not_to include(sensitive_value)
        expect(contents).to include("--upstream-token XXXXXXX")
      end
    end

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

  describe ".create_app_if_not_exists" do
    let(:app) { "#{described_class::DUMMY_TEST_APP_PREFIX}-default-ab12" }
    let(:success) { { status: ExitCode::SUCCESS, stdout: "", stderr: "" } }
    let(:not_found) { { status: ExitCode::NOT_FOUND, stdout: "", stderr: "" } }

    around do |example|
      registered = described_class.apps_to_delete.dup
      incomplete = described_class.incomplete_apps.dup
      example.run
      described_class.apps_to_delete.replace(registered)
      described_class.incomplete_apps.replace(incomplete)
    end

    it "reuses an existing app without preparing or deleting it" do
      allow(described_class).to receive(:run_cpflow_command).with("exists", "-a", app).and_return(success)
      allow(described_class).to receive(:run_cpflow_command!)

      result = described_class.create_app_if_not_exists(app)

      expect(result).to eq(app)
      expect(described_class).not_to have_received(:run_cpflow_command).with("delete", "-a", app, "--yes")
      expect(described_class).not_to have_received(:run_cpflow_command!)
    end

    it "does not reuse an incomplete app while an accepted deletion is converging" do
      described_class.incomplete_apps.push(app)
      allow(described_class).to receive(:run_cpflow_command).with("exists", "-a", app).and_return(success)
      allow(described_class).to receive(:run_cpflow_command).with("delete", "-a", app, "--yes").and_return(success)
      allow(described_class).to receive(:run_cpflow_command!)

      expect { described_class.create_app_if_not_exists(app) }
        .to raise_error(RuntimeError, /Refusing to reuse incomplete test app/)
      expect(described_class).not_to have_received(:run_cpflow_command!)
      expect(described_class.incomplete_apps).to include(app)
    end

    it "fails closed when the existence lookup returns an unexpected status" do
      lookup_failure = { status: ExitCode::ERROR_DEFAULT, stdout: "", stderr: "backend unavailable" }
      allow(described_class).to receive(:run_cpflow_command).with("exists", "-a", app).and_return(lookup_failure)
      allow(described_class).to receive(:run_cpflow_command!)

      expect { described_class.create_app_if_not_exists(app) }
        .to raise_error(RuntimeError, /cpflow exists exited with status 64/)
      expect(described_class).not_to have_received(:run_cpflow_command!)
    end

    it "deletes an incomplete app and preserves the preparation error" do
      preparation_error = RuntimeError.new("build failed")
      allow(described_class).to receive(:run_cpflow_command).with("exists", "-a", app).and_return(not_found)
      allow(described_class).to receive(:run_cpflow_command).with("delete", "-a", app, "--yes").and_return(success)
      allow(described_class).to receive(:run_cpflow_command!).with(
        "setup-app", "-a", app, "--skip-secrets-setup"
      )
      allow(described_class).to receive(:run_cpflow_command!).with("build-image", "-a", app)
                                                             .and_raise(preparation_error)

      same_error = raise_error(RuntimeError) { |error| expect(error).to equal(preparation_error) }
      expect { described_class.create_app_if_not_exists(app, image_before_deploy_count: 1) }.to same_error
      expect(described_class).to have_received(:run_cpflow_command).with("delete", "-a", app, "--yes").once
      expect(described_class.apps_to_delete).to include(app)
    end

    it "preserves the preparation error when cleanup returns a failure" do
      preparation_error = RuntimeError.new("setup failed")
      cleanup_failure = { status: ExitCode::ERROR_DEFAULT, stdout: "", stderr: "delete failed" }
      allow(described_class).to receive(:run_cpflow_command).with("exists", "-a", app).and_return(not_found)
      allow(described_class).to receive(:run_cpflow_command).with("delete", "-a", app, "--yes")
                                                            .and_return(cleanup_failure)
      allow(described_class).to receive(:run_cpflow_command!).and_raise(preparation_error)
      allow(described_class).to receive(:warn)

      same_error = raise_error(RuntimeError) { |error| expect(error).to equal(preparation_error) }
      expect { described_class.create_app_if_not_exists(app) }.to same_error
      expect(described_class).to have_received(:warn).with(include("exit status 64"))
    end

    it "preserves the preparation error when cleanup raises" do
      preparation_error = RuntimeError.new("setup failed")
      allow(described_class).to receive(:run_cpflow_command).with("exists", "-a", app).and_return(not_found)
      allow(described_class).to receive(:run_cpflow_command).with("delete", "-a", app, "--yes")
                                                            .and_raise("delete crashed")
      allow(described_class).to receive(:run_cpflow_command!).and_raise(preparation_error)
      allow(described_class).to receive(:warn)

      same_error = raise_error(RuntimeError) { |error| expect(error).to equal(preparation_error) }
      expect { described_class.create_app_if_not_exists(app) }.to same_error
      expect(described_class).to have_received(:warn).with(include("RuntimeError"))
    end

    it "keeps an incomplete app when suite cleanup is disabled" do
      preparation_error = RuntimeError.new("setup failed")
      stub_env("SKIP_CLEANUP", "true")
      allow(described_class).to receive(:run_cpflow_command).with("exists", "-a", app).and_return(not_found)
      allow(described_class).to receive(:run_cpflow_command!).and_raise(preparation_error)

      expect { described_class.create_app_if_not_exists(app) }.to raise_error(preparation_error)
      expect(described_class).not_to have_received(:run_cpflow_command).with("delete", "-a", app, "--yes")
    end

    it "does not reuse after failed cleanup and recreates once deletion finishes" do
      preparation_error = RuntimeError.new("first setup failed")
      setup_attempts = 0
      cleanup_failure = { status: ExitCode::ERROR_DEFAULT, stdout: "", stderr: "delete failed" }
      allow(described_class).to receive(:run_cpflow_command).with("exists", "-a", app)
                                                            .and_return(not_found, success, not_found)
      allow(described_class).to receive(:run_cpflow_command).with("delete", "-a", app, "--yes")
                                                            .and_return(cleanup_failure, success)
      allow(described_class).to receive(:run_cpflow_command!).with(
        "setup-app", "-a", app, "--skip-secrets-setup"
      ) do
        setup_attempts += 1
        raise preparation_error if setup_attempts == 1

        success
      end
      allow(described_class).to receive(:warn)

      expect { described_class.create_app_if_not_exists(app) }.to raise_error(preparation_error)
      expect { described_class.create_app_if_not_exists(app) }
        .to raise_error(RuntimeError, /Refusing to reuse incomplete test app/)
      expect(described_class.create_app_if_not_exists(app)).to eq(app)
      expect(described_class).to have_received(:run_cpflow_command!).with(
        "setup-app", "-a", app, "--skip-secrets-setup"
      ).twice
      expect(described_class.incomplete_apps).not_to include(app)
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
