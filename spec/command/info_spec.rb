# frozen_string_literal: true

require "spec_helper"

describe Command::Info do
  before do
    allow_any_instance_of(described_class).to receive(:app_org).and_return(dummy_test_org) # rubocop:disable RSpec/AnyInstance
  end

  context "when 'cpln_org' is not defined for app" do
    let!(:app_prefix) { dummy_test_app_prefix("info") }

    before do
      allow_any_instance_of(described_class).to receive(:app_org).with(app_prefix.to_sym, anything).and_call_original # rubocop:disable RSpec/AnyInstance
    end

    it "does not include app" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-a", app_prefix)

      expect(Shell).not_to have_received(:color)
        .with(include("Any app starting with '#{app_prefix}'"), :red)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).not_to include("`cpl setup-app -a #{app_prefix}-whatever`")
    end
  end

  context "when nothing is missing" do
    let!(:app_prefix) { dummy_test_app_prefix("info-with-nothing-missing") }
    let!(:app1) { dummy_test_app("info-with-nothing-missing", "1", create_if_not_exists: true) }
    let!(:app2) { dummy_test_app("info-with-nothing-missing", "2", create_if_not_exists: true) }

    it "does not highlight anything for single app" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-a", app1)

      expect(Shell).not_to have_received(:color).with(app1, :red)
      expect(Shell).not_to have_received(:color).with("rails", :red)
      expect(Shell).not_to have_received(:color).with("redis", :red)
      expect(Shell).not_to have_received(:color).with("postgres", :red)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).not_to include("- #{app2}")
      expect(result[:stdout]).not_to include("cpl setup-app")
      expect(result[:stdout]).not_to include("cpl apply-template")
    end

    it "does not highlight anything for multiple apps" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-a", app_prefix)

      expect(Shell).not_to have_received(:color)
        .with(include("Any app starting with '#{app_prefix}'"), :red)
      expect(Shell).not_to have_received(:color).with("rails", :red)
      expect(Shell).not_to have_received(:color).with("redis", :red)
      expect(Shell).not_to have_received(:color).with("postgres", :red)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).to include("- #{app2}")
      expect(result[:stdout]).not_to include("cpl setup-app")
      expect(result[:stdout]).not_to include("cpl apply-template")
    end
  end

  context "when there are apps missing" do
    let!(:app_prefix) { dummy_test_app_prefix("info-with-missing-apps") }
    let!(:app1) { dummy_test_app("info-with-missing-apps") }
    let!(:app2) { dummy_test_app("info-with-missing-apps") }

    it "highlights single app with red" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-a", app1)

      expect(Shell).to have_received(:color).with(app1, :red)
      expect(Shell).to have_received(:color).with("rails", :red)
      expect(Shell).to have_received(:color).with("redis", :red)
      expect(Shell).to have_received(:color).with("postgres", :red)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).not_to include("- #{app2}")
      expect(result[:stdout]).to include("`cpl setup-app -a #{app1}`")
    end

    it "highlights multiple apps with red" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-a", app_prefix)

      expect(Shell).to have_received(:color)
        .with(include("Any app starting with '#{app_prefix}'"), :red)
      expect(Shell).to have_received(:color).with("rails", :red).at_least(:once)
      expect(Shell).to have_received(:color).with("redis", :red).at_least(:once)
      expect(Shell).to have_received(:color).with("postgres", :red).at_least(:once)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).not_to include("- #{app1}")
      expect(result[:stdout]).not_to include("- #{app2}")
      expect(result[:stdout]).to include("`cpl setup-app -a #{app_prefix}-whatever`")
    end

    it "highlights apps for single org with red" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-o", dummy_test_org)

      expect(Shell).to have_received(:color)
        .with(include("Any app starting with '#{app_prefix}'"), :red)
      expect(Shell).to have_received(:color).with("rails", :red).at_least(:once)
      expect(Shell).to have_received(:color).with("redis", :red).at_least(:once)
      expect(Shell).to have_received(:color).with("postgres", :red).at_least(:once)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).not_to include("- #{app1}")
      expect(result[:stdout]).not_to include("- #{app2}")
      expect(result[:stdout]).to include("`cpl setup-app -a #{app_prefix}-whatever`")
    end

    it "highlights apps for multiple orgs with red" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info")

      expect(Shell).to have_received(:color)
        .with(include("Any app starting with '#{app_prefix}'"), :red)
      expect(Shell).to have_received(:color).with("rails", :red).at_least(:once)
      expect(Shell).to have_received(:color).with("redis", :red).at_least(:once)
      expect(Shell).to have_received(:color).with("postgres", :red).at_least(:once)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).not_to include("- #{app1}")
      expect(result[:stdout]).not_to include("- #{app2}")
      expect(result[:stdout]).to include("`cpl setup-app -a #{app_prefix}-whatever`")
    end
  end

  context "when there are workloads missing" do
    let!(:app_prefix) { dummy_test_app_prefix("info-with-missing-workloads") }
    let!(:app1) { dummy_test_app("info-with-missing-workloads", "1", create_if_not_exists: true) }
    let!(:app2) { dummy_test_app("info-with-missing-workloads", "2", create_if_not_exists: true) }

    it "highlights workloads for single app with red" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-a", app1)

      expect(Shell).not_to have_received(:color).with(app1, :red)
      expect(Shell).not_to have_received(:color).with("rails", :red)
      expect(Shell).to have_received(:color).with("redis", :red)
      expect(Shell).to have_received(:color).with("postgres", :red)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).not_to include("- #{app2}")
      expect(result[:stdout]).to include("`cpl apply-template redis postgres -a #{app1}`")
    end

    it "highlights workloads for multiple apps with red" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-a", app_prefix)

      expect(Shell).not_to have_received(:color).with(app1, :red)
      expect(Shell).not_to have_received(:color).with(app2, :red)
      expect(Shell).to have_received(:color).with("redis", :red).at_least(:once)
      expect(Shell).to have_received(:color).with("postgres", :red).at_least(:once)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).to include("- #{app2}")
      expect(result[:stdout]).to include("`cpl apply-template redis postgres -a #{app1}`")
      expect(result[:stdout]).to include("`cpl apply-template redis postgres -a #{app2}`")
    end

    it "highlights workloads for single org with red" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-o", dummy_test_org)

      expect(Shell).not_to have_received(:color).with(app1, :red)
      expect(Shell).not_to have_received(:color).with(app2, :red)
      expect(Shell).to have_received(:color).with("redis", :red).at_least(:once)
      expect(Shell).to have_received(:color).with("postgres", :red).at_least(:once)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).to include("- #{app2}")
      expect(result[:stdout]).to include("`cpl apply-template redis postgres -a #{app1}`")
      expect(result[:stdout]).to include("`cpl apply-template redis postgres -a #{app2}`")
    end

    it "highlights workloads for multiple orgs with red" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info")

      expect(Shell).not_to have_received(:color).with(app1, :red)
      expect(Shell).not_to have_received(:color).with(app2, :red)
      expect(Shell).to have_received(:color).with("redis", :red).at_least(:once)
      expect(Shell).to have_received(:color).with("postgres", :red).at_least(:once)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).to include("- #{app2}")
      expect(result[:stdout]).to include("`cpl apply-template redis postgres -a #{app1}`")
      expect(result[:stdout]).to include("`cpl apply-template redis postgres -a #{app2}`")
    end
  end

  context "when there are extra workloads" do
    let!(:app_prefix) { dummy_test_app_prefix("info-with-extra-workloads") }
    let!(:app1) { dummy_test_app("info-with-extra-workloads", "1", create_if_not_exists: true) }
    let!(:app2) { dummy_test_app("info-with-extra-workloads", "2", create_if_not_exists: true) }

    it "highlights workloads for single app with green" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-a", app1)

      expect(Shell).not_to have_received(:color).with(app1, :red)
      expect(Shell).not_to have_received(:color).with("rails", :red)
      expect(Shell).not_to have_received(:color).with("redis", :red)
      expect(Shell).not_to have_received(:color).with("postgres", :red)
      expect(Shell).to have_received(:color).with("rails-with-non-app-image", :green)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).not_to include("- #{app2}")
      expect(result[:stdout]).not_to include("cpl setup-app")
      expect(result[:stdout]).not_to include("cpl apply-template")
    end

    it "highlights workloads for multiple apps with green" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-a", app_prefix)

      expect(Shell).not_to have_received(:color).with(app1, :red)
      expect(Shell).not_to have_received(:color).with(app2, :red)
      expect(Shell).to have_received(:color).with("rails-with-non-app-image", :green).at_least(:once)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).to include("- #{app2}")
      expect(result[:stdout]).not_to include("`cpl setup-app -a #{app_prefix}-whatever`")
    end

    it "highlights workloads for single org with green" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info", "-o", dummy_test_org)

      expect(Shell).not_to have_received(:color).with(app1, :red)
      expect(Shell).not_to have_received(:color).with(app2, :red)
      expect(Shell).to have_received(:color).with("rails-with-non-app-image", :green).at_least(:once)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).to include("- #{app2}")
      expect(result[:stdout]).not_to include("`cpl setup-app -a #{app_prefix}-whatever`")
    end

    it "highlights workloads for multiple orgs with green" do
      allow(Shell).to receive(:color).and_call_original

      result = run_cpl_command("info")

      expect(Shell).not_to have_received(:color).with(app1, :red)
      expect(Shell).not_to have_received(:color).with(app2, :red)
      expect(Shell).to have_received(:color).with("rails-with-non-app-image", :green).at_least(:once)
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include("- #{app1}")
      expect(result[:stdout]).to include("- #{app2}")
      expect(result[:stdout]).not_to include("`cpl setup-app -a #{app_prefix}-whatever`")
    end
  end
end
