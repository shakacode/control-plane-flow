# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/IndexedLet
describe Command::CleanupStaleApps do
  let!(:app_prefix) { dummy_test_app_prefix("stale-app") }

  describe ".OPTIONS" do
    it "keeps the cleanup mode option scoped to cleanup-stale-apps" do
      expect(described_class::OPTIONS.map { |option| option[:name] }).to include(:mode)
      expect(Command::Base.all_options.map { |option| option[:name] }).not_to include(:mode)
    end
  end

  describe "#confirm_action" do
    let(:config) { instance_double(Config, options: { mode: mode, yes: false }) }
    let(:command) { described_class.new(config) }

    before do
      allow(command).to receive(:stale_apps).and_return([{ name: "app-1" }, { name: "app-2" }])
      allow(Shell).to receive(:confirm).and_return(false)
    end

    context "with delete mode" do
      let(:mode) { "delete" }

      it "confirms app deletion" do
        command.send(:confirm_action)

        expect(Shell).to have_received(:confirm).with(include("delete these 2 apps"))
      end
    end

    context "with stop mode" do
      let(:mode) { "stop" }

      it "confirms workload suspension" do
        command.send(:confirm_action)

        expect(Shell).to have_received(:confirm).with(include("suspend all workloads in these 2 apps"))
      end
    end
  end

  describe "#stale_apps" do
    let(:config) { instance_double(Config, app: "dummy-test") }
    let(:cp) { instance_double(Controlplane) }
    let(:command) { described_class.new(config) }
    let(:gvc) { { "name" => "dummy-test-image-less", "created" => "2000-01-01T00:00:00Z" } }

    before do
      allow(config).to receive(:[]).with(:stale_app_image_deployed_days).and_return(5)
      allow(command).to receive(:cp).and_return(cp)
      allow(cp).to receive(:gvc_query).with("dummy-test").and_return({ "items" => [gvc] })
      allow(cp).to receive(:query_images).with(gvc.fetch("name")).and_return({ "items" => [] })
      allow(cp).to receive(:latest_image_from)
        .with([], app_name: gvc.fetch("name"), name_only: false)
        .and_return(nil)
    end

    it "uses the GVC creation date when the app has no images" do
      expect(command.send(:stale_apps)).to eq([
                                                {
                                                  name: gvc.fetch("name"),
                                                  date: DateTime.parse(gvc.fetch("created"))
                                                }
                                              ])
    end

    context "when the GVC has no creation date" do
      let(:gvc) { { "name" => "dummy-test-image-less", "created" => nil } }

      it "skips the app instead of raising" do
        expect(command.send(:stale_apps)).to eq([])
      end
    end
  end

  describe "#process_app" do
    let(:config) do
      instance_double(
        Config,
        options: { mode: "stop" },
        find_app_config: {
          app_workloads: ["rails"],
          additional_workloads: ["postgres"]
        }
      )
    end
    let(:cp) do
      instance_double(
        Controlplane,
        fetch_workloads: {
          "items" => [
            { "name" => "postgres" },
            { "name" => "unconfigured-worker" }
          ]
        }
      )
    end
    let(:command) { described_class.new(config) }

    before do
      allow(command).to receive(:cp).and_return(cp)
      allow(command).to receive(:run_cpflow_command)
    end

    it "stops only configured workloads that exist in the stale app" do
      command.send(:process_app, "stale-app")

      expect(cp).to have_received(:fetch_workloads).with("stale-app")
      expect(command).to have_received(:run_cpflow_command)
        .with("ps:stop", "-a", "stale-app", "--workload", "postgres").once
      expect(command).not_to have_received(:run_cpflow_command)
        .with("ps:stop", "-a", "stale-app", "--workload", "rails")
      expect(command).not_to have_received(:run_cpflow_command)
        .with("ps:stop", "-a", "stale-app", "--workload", "unconfigured-worker")
    end
  end

  context "when 'stale_app_image_deployed_days' is not defined" do
    let!(:app) { dummy_test_app("nothing") }

    it "raises error" do
      result = run_cpflow_command("cleanup-stale-apps", "-a", app)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Can't find option 'stale_app_image_deployed_days'")
    end
  end

  context "when --mode value is invalid" do
    let!(:app) { dummy_test_app }

    it "rejects the command" do
      result = run_cpflow_command("cleanup-stale-apps", "-a", app, "--mode=pause")

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("Invalid value provided for option --mode.")
    end
  end

  context "when there are no stale apps to act on" do
    let!(:app) { dummy_test_app }

    it "displays message" do
      result = run_cpflow_command("cleanup-stale-apps", "-a", app)

      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("No stale apps found")
    end
  end

  context "when there are stale apps" do
    let!(:app1) { dummy_test_app("stale-app") }
    let!(:app2) { dummy_test_app("stale-app") }

    before do
      run_cpflow_command!("apply-template", "app", "postgres-with-volume", "-a", app1)
      run_cpflow_command!("apply-template", "app", "postgres-with-volume", "-a", app2)
      run_cpflow_command!("build-image", "-a", app1)
      run_cpflow_command!("build-image", "-a", app2)
    end

    after do
      run_cpflow_command!("delete", "-a", app1, "--yes")
      run_cpflow_command!("delete", "-a", app2, "--yes")
    end

    it "asks for confirmation and does nothing", :slow do
      allow(Shell).to receive(:confirm).with(include("delete these 2 apps")).and_return(false)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-stale-apps", "-a", app_prefix)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Deleting app")
    end

    it "uses workload-suspension wording when --mode=stop and does nothing on declined confirmation", :slow do
      allow(Shell).to receive(:confirm).with(include("suspend all workloads in these 2 apps")).and_return(false)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-stale-apps", "-a", app_prefix, "--mode=stop")
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Deleting app")
      expect(result[:stderr]).not_to include("Stopping workload")
    end

    it "asks for confirmation and stops stale apps when --mode=stop", :slow do
      allow(Shell).to receive(:confirm).with(include("suspend all workloads in these 2 apps")).and_return(true)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-stale-apps", "-a", app_prefix, "--mode=stop")
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Deleting app")
      # Per-app header gives the workload-stop output app-name context in CI logs.
      expect(result[:stderr]).to include("Stopping app '#{app1}'")
      expect(result[:stderr]).to include("Stopping app '#{app2}'")
      stop_lines = result[:stderr].scan(/Stopping workload 'postgres'[.]+? done!/)
      expect(stop_lines.length).to eq(2),
                                   "expected exactly 2 'Stopping workload postgres' lines; got: #{result[:stderr]}"
    end

    it "asks for confirmation and deletes stale apps", :slow do
      allow(Shell).to receive(:confirm).with(include("delete these 2 apps")).and_return(true)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-stale-apps", "-a", app_prefix)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting volumeset 'postgres-volume' from app '#{app1}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting app '#{app1}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting image '#{app1}:1' from app '#{app1}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting volumeset 'postgres-volume' from app '#{app2}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting app '#{app2}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting image '#{app2}:1' from app '#{app2}'[.]+? done!/)
    end

    it "skips confirmation and deletes stale apps", :slow do
      allow(Shell).to receive(:confirm).and_return(false)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-stale-apps", "-a", app_prefix, "--yes")
      travel_back

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to match(/Deleting volumeset 'postgres-volume' from app '#{app1}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting app '#{app1}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting image '#{app1}:1' from app '#{app1}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting volumeset 'postgres-volume' from app '#{app2}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting app '#{app2}'[.]+? done!/)
      expect(result[:stderr]).to match(/Deleting image '#{app2}:1' from app '#{app2}'[.]+? done!/)
    end

    it "skips confirmation and stops stale apps when --mode=stop --yes", :slow do
      allow(Shell).to receive(:confirm).and_return(false)

      travel_to_days_later(30)
      result = run_cpflow_command("cleanup-stale-apps", "-a", app_prefix, "--mode=stop", "--yes")
      travel_back

      expect(Shell).not_to have_received(:confirm)
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).not_to include("Deleting app")
      # Per-app header gives the workload-stop output app-name context in CI logs.
      expect(result[:stderr]).to include("Stopping app '#{app1}'")
      expect(result[:stderr]).to include("Stopping app '#{app2}'")
      stop_lines = result[:stderr].scan(/Stopping workload 'postgres'[.]+? done!/)
      expect(stop_lines.length).to eq(2),
                                   "expected exactly 2 'Stopping workload postgres' lines; got: #{result[:stderr]}"
    end
  end

  context "with multiple apps" do
    let!(:app1) { dummy_test_app("stale-app") }
    let!(:app2) { dummy_test_app("stale-app") }
    let!(:app3) { dummy_test_app("stale-app") }
    let!(:app4) { dummy_test_app("stale-app") }

    before do
      run_cpflow_command!("apply-template", "app", "-a", app1)
      run_cpflow_command!("apply-template", "app", "-a", app2)
      run_cpflow_command!("apply-template", "app", "-a", app3)
      run_cpflow_command!("apply-template", "app", "-a", app4)
    end

    after do
      run_cpflow_command!("delete", "-a", app1, "--yes")
      run_cpflow_command!("delete", "-a", app2, "--yes")
      run_cpflow_command!("delete", "-a", app3, "--yes")
      run_cpflow_command!("delete", "-a", app4, "--yes")
    end

    it "lists correct stale apps", :slow do
      allow(Shell).to receive(:confirm).with(include("3 apps")).and_return(false)

      # We need to stub the image from app3 to have the current date,
      # as Control Plane does not allow manipulating the creation date of an image
      allow_any_instance_of(Controlplane).to receive(:query_images).and_wrap_original do |original, *args, &block| # rubocop:disable RSpec/AnyInstance
        original_return = original.call(*args, &block)
        original_return["items"].each do |item|
          item["created"] = Time.now.to_s if item["name"].start_with?("#{app3}:")
        end
        original_return
      end

      # Apps with old image, will be listed
      run_cpflow_command!("build-image", "-a", app1)
      run_cpflow_command!("build-image", "-a", app2)
      travel_to_days_later(30)
      # App with new image, wont't be listed
      run_cpflow_command!("build-image", "-a", app3)
      # app4 has no image; its old GVC date is used as the fallback, so it is listed
      result = run_cpflow_command("cleanup-stale-apps", "-a", app_prefix)
      travel_back

      expect(Shell).to have_received(:confirm).once
      expect(result[:status]).to eq(0)
      expect(result[:stderr]).to include("- #{app1}")
      expect(result[:stderr]).to include("- #{app2}")
      expect(result[:stderr]).not_to include("- #{app3}")
      expect(result[:stderr]).to include("- #{app4}")
    end
  end
end
# rubocop:enable RSpec/IndexedLet
