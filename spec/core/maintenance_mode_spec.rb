# frozen_string_literal: true

require "spec_helper"

describe MaintenanceMode do
  let(:config) { instance_double(Config, app: "my-app", domain: nil, current: { maintenance_workload: "maintenance" }) }
  let(:command) { Command::Base.new(config) }
  let(:cp) { instance_double(Controlplane) }
  let(:command_calls) { [] }

  before do
    allow(config).to receive(:[]).with(:one_off_workload).and_return("web")
    allow(command).to receive_messages(cp: cp, progress: StringIO.new)
    allow(command).to receive(:run_cpflow_command) { |*args| command_calls << args }
    allow(Kernel).to receive(:sleep).and_return(0)
    allow(cp).to receive(:fetch_workload!)
    allow(cp).to receive(:set_domain_workload)
    allow(cp).to receive(:domain_workload_matches?) do |data, workload|
      domain_routed_to_workload?(data, workload)
    end
  end

  describe "#enable!" do
    before do
      stub_domain_switch(from: "web", to: "maintenance")
    end

    it "waits for the fetched domain route to point at the maintenance workload" do
      described_class.new(command).enable!

      expect_domain_update_requested_for("maintenance")
      expect(cp).to have_received(:fetch_domain).with("my-app.example.com").twice
      expect(command_calls).to eq(expected_switch_commands)
    end
  end

  describe "#disable!" do
    before do
      stub_domain_switch(from: "maintenance", to: "web")
    end

    it "waits for the fetched domain route to point at the app workload" do
      described_class.new(command).disable!

      expect_domain_update_requested_for("web")
      expect(cp).to have_received(:fetch_domain).with("my-app.example.com").twice
      expect(command_calls).to eq(expected_switch_commands)
    end
  end

  def stub_domain_switch(from:, to:)
    allow(cp).to receive(:find_domain_for).and_return(domain_routed_to(from))
    allow(cp).to receive(:fetch_domain).with("my-app.example.com").and_return(
      domain_routed_to(from),
      domain_routed_to(to)
    )
  end

  def expect_domain_update_requested_for(workload)
    expect(cp).to have_received(:set_domain_workload).once do |domain_data, requested_workload|
      expect(domain_data["name"]).to eq("my-app.example.com")
      expect(requested_workload).to eq(workload)
    end
  end

  def expected_switch_commands
    [
      ["ps:start", "-a", "my-app", "-w", "maintenance", "--wait"],
      ["ps:stop", "-a", "my-app", "--wait"]
    ]
  end

  def domain_routed_to_workload?(data, workload)
    data.dig("spec", "ports").any? do |port|
      port["routes"].any? do |route|
        route["prefix"] == "/" && route["workloadLink"].end_with?("/workload/#{workload}")
      end
    end
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
