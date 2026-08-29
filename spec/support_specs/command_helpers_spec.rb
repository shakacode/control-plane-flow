# frozen_string_literal: true

require "spec_helper"

describe CommandHelpers do
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
end
