# frozen_string_literal: true

RSpec.shared_examples "validates domain existence" do |command:|
  context "when app has no domain" do
    let!(:app) { dummy_test_app("nothing") }

    it "raises error" do
      result = run_cpflow_command(command, "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find domain")
    end
  end
end

RSpec.shared_examples "validates maintenance workload existence" do |command:|
  context "when maintenance workload does not exist" do
    let!(:app) { dummy_test_app("default", create_if_not_exists: true) }

    it "raises error" do
      result = run_cpflow_command(command, "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find workload 'maintenance'")
    end
  end
end

RSpec.shared_examples "switches maintenance mode command" do |action:|
  include_examples "validates domain existence", command: "maintenance:#{action}"
  include_examples "validates maintenance workload existence", command: "maintenance:#{action}"

  context "when maintenance workload exists" do
    let!(:app) { dummy_test_app("full", create_if_not_exists: true) }

    let(:command) { "maintenance:#{action}" }
    let(:opposite_command) { "maintenance:#{enable?(action) ? 'off' : 'on'}" }
    let(:state) { enable?(action) ? "enabled" : "disabled" }

    before do
      allow(Kernel).to receive(:sleep)

      run_cpflow_command!("ps:start", "-a", app, "--wait")
    end

    it "does nothing if maintenance mode is already in desired state", :slow do
      run_cpflow_command!(command, "-a", app)
      result = run_cpflow_command(command, "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Maintenance mode is already #{state} for app '#{app}'")
    end

    it "switches maintenance mode state", :slow do
      run_cpflow_command!(opposite_command, "-a", app)
      result = run_cpflow_command(command, "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("Maintenance mode #{state} for app '#{app}'")
    end

    def enable?(action)
      action.to_s == "on"
    end
  end
end
