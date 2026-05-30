# frozen_string_literal: true

require "spec_helper"

describe MaintenanceMode do
  let(:config) { instance_double(Config, app: "my-app", domain: nil, current: { maintenance_workload: "maintenance" }) }
  let(:command) { Command::Base.new(config) }
  let(:cp) do
    Controlplane.allocate.tap do |controlplane|
      controlplane.instance_variable_set(:@api, instance_double(ControlplaneApi, update_domain: true))
      controlplane.instance_variable_set(:@gvc, "my-app")
      controlplane.instance_variable_set(:@org, "my-org")
    end
  end
  let(:progress) { StringIO.new }
  let(:command_calls) { [] }

  before do
    allow(config).to receive(:[]).with(:one_off_workload).and_return("web")
    allow(command).to receive_messages(cp: cp, progress: progress)
    allow(command).to receive(:run_cpflow_command) { |*args| command_calls << args }
    allow(Kernel).to receive(:sleep).and_return(0)
    allow(cp).to receive(:fetch_workload!)
    allow(cp).to receive(:set_domain_workload).and_call_original
  end

  describe "#enable!" do
    it "waits for the fetched domain route to point at the maintenance workload" do
      stub_domain_switch(from: "web", to: "maintenance")

      described_class.new(command).enable!

      expect_domain_update_requested_for("maintenance")
      expect(cp).to have_received(:fetch_domain).with("my-app.example.com").twice
      expect(command_calls).to eq(expected_workload_commands)
    end

    it "continues polling when the fetched domain temporarily has no routable route" do
      stub_domain_switch(from: "web", to: "maintenance", polls: [nil, domain_routed_to("maintenance")])

      described_class.new(command).enable!

      expect_domain_update_requested_for("maintenance")
      expect(cp).to have_received(:fetch_domain).with("my-app.example.com").twice
      expect(command_calls).to eq(expected_workload_commands)
    end

    it "continues polling when a transient API error is raised mid-switch" do
      allow(cp).to receive(:find_domain_for).and_return(domain_routed_to("web"))
      poll_responses = [->(*) { raise "transient API error" }, ->(*) { domain_routed_to("maintenance") }]
      allow(cp).to receive(:fetch_domain).with("my-app.example.com").and_invoke(*poll_responses)

      described_class.new(command).enable!

      expect_domain_update_requested_for("maintenance")
      expect(cp).to have_received(:fetch_domain).with("my-app.example.com").twice
      expect(command_calls).to eq(expected_workload_commands)
    end

    it "stops after the bounded retry count when the domain route never updates" do
      stub_domain_switch(from: "web", to: "maintenance", polls: [domain_routed_to("web")])

      expect { described_class.new(command).enable! }.to raise_error(SystemExit) { |error| expect(error.status).to eq(ExitCode::ERROR_DEFAULT) }

      expect_domain_update_requested_for("maintenance")
      expect(cp).to have_received(:fetch_domain).with("my-app.example.com")
                                                .exactly(MaintenanceMode::DOMAIN_WORKLOAD_UPDATE_MAX_POLL_ATTEMPTS).times
      expect(command_calls).to eq([["ps:start", "-a", "my-app", "-w", "maintenance", "--wait"]])
    end

    it "skips work when maintenance mode is already enabled" do
      allow(cp).to receive(:find_domain_for).and_return(domain_routed_to("maintenance"))

      described_class.new(command).enable!

      expect(cp).not_to have_received(:fetch_workload!)
      expect(cp).not_to have_received(:set_domain_workload)
      expect(command_calls).to be_empty
      expect(progress.string).to include("Maintenance mode is already enabled for app 'my-app'.")
    end

    it "keeps cached domain data when polling never returns a routable domain" do
      maintenance_mode = described_class.new(command)

      stub_domain_switch(from: "web", to: "maintenance", polls: [nil])

      expect { maintenance_mode.enable! }.to raise_error(SystemExit) { |error| expect(error.status).to eq(ExitCode::ERROR_DEFAULT) }

      expect(maintenance_mode.disabled?).to be(true)
      expect(cp).to have_received(:find_domain_for).once
    end
  end

  describe "#disable!" do
    it "waits for the fetched domain route to point at the app workload" do
      stub_domain_switch(from: "maintenance", to: "web")

      described_class.new(command).disable!

      expect_domain_update_requested_for("web")
      expect(cp).to have_received(:fetch_domain).with("my-app.example.com").twice
      expect(command_calls).to eq(expected_workload_commands)
    end

    it "continues polling when the fetched domain temporarily has no routable route" do
      stub_domain_switch(from: "maintenance", to: "web", polls: [nil, domain_routed_to("web")])

      described_class.new(command).disable!

      expect_domain_update_requested_for("web")
      expect(cp).to have_received(:fetch_domain).with("my-app.example.com").twice
      expect(command_calls).to eq(expected_workload_commands)
    end

    it "continues polling when a transient API error is raised mid-switch" do
      allow(cp).to receive(:find_domain_for).and_return(domain_routed_to("maintenance"))
      poll_responses = [->(*) { raise "transient API error" }, ->(*) { domain_routed_to("web") }]
      allow(cp).to receive(:fetch_domain).with("my-app.example.com").and_invoke(*poll_responses)

      described_class.new(command).disable!

      expect_domain_update_requested_for("web")
      expect(cp).to have_received(:fetch_domain).with("my-app.example.com").twice
      expect(command_calls).to eq(expected_workload_commands)
    end

    it "skips work when maintenance mode is already disabled" do
      allow(cp).to receive(:find_domain_for).and_return(domain_routed_to("web"))

      described_class.new(command).disable!

      expect(cp).not_to have_received(:fetch_workload!)
      expect(cp).not_to have_received(:set_domain_workload)
      expect(command_calls).to be_empty
      expect(progress.string).to include("Maintenance mode is already disabled for app 'my-app'.")
    end

    it "stops after the bounded retry count when the domain route never updates" do
      stub_domain_switch(from: "maintenance", to: "web", polls: [domain_routed_to("maintenance")])

      expect { described_class.new(command).disable! }.to raise_error(SystemExit) { |error| expect(error.status).to eq(ExitCode::ERROR_DEFAULT) }

      expect_domain_update_requested_for("web")
      expect(cp).to have_received(:fetch_domain).with("my-app.example.com")
                                                .exactly(MaintenanceMode::DOMAIN_WORKLOAD_UPDATE_MAX_POLL_ATTEMPTS).times
      expect(command_calls).to eq([["ps:start", "-a", "my-app", "-w", "maintenance", "--wait"]])
    end
  end

  def stub_domain_switch(from:, to:, polls: nil)
    allow(cp).to receive(:find_domain_for).and_return(domain_routed_to(from))
    # Default polls: the first fetch still sees the old route (simulates one
    # in-flight propagation delay) and the second sees the new route. RSpec
    # repeats the final value on any further calls, so this also covers polls
    # that exhaust the retry budget on a single repeated value.
    allow(cp).to receive(:fetch_domain).with("my-app.example.com").and_return(
      *(polls || [domain_routed_to(from), domain_routed_to(to)])
    )
  end

  def expect_domain_update_requested_for(workload)
    expect(cp).to have_received(:set_domain_workload).once do |domain_data, requested_workload|
      expect(domain_data["name"]).to eq("my-app.example.com")
      expect(requested_workload).to eq(workload)
    end
  end

  def expected_workload_commands
    [
      ["ps:start", "-a", "my-app", "-w", "maintenance", "--wait"],
      ["ps:stop", "-a", "my-app", "--wait"]
    ]
  end

  def domain_routed_to(workload)
    {
      "name" => "my-app.example.com",
      "spec" => { "ports" => [domain_port_routed_to(workload)] }
    }
  end

  def domain_port_routed_to(workload)
    {
      "number" => 443,
      "routes" => [
        {
          "prefix" => "/",
          "workloadLink" => "/org/my-org/gvc/my-app/workload/#{workload}"
        }
      ]
    }
  end
end
