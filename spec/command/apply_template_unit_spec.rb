# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
describe Command::ApplyTemplate do
  describe "#call" do
    let(:options) { { yes: true, preserve_existing_runtime: true } }
    let(:config) do
      instance_double(
        Config,
        args: %w[postgres rails worker],
        options: options,
        app: "test-review-123",
        org: "test-org",
        identity: "test-review-123-identity",
        current: { app_workloads: app_workloads }
      )
    end
    let(:app_workloads) { %w[rails worker] }
    let(:cp) { instance_double(Controlplane) }
    let(:parser) { instance_double(TemplateParser) }
    let(:command) { described_class.new(config) }
    let(:latest_image) { "/org/test-org/image/test-review-123:9_bad" }
    let(:deployed_image) { "/org/test-org/image/test-review-123:8_good" }
    let(:templates) do
      [
        {
          "kind" => "secret",
          "name" => "test-review-123-pg",
          "type" => "dictionary",
          "data" => { "password" => "template-placeholder" }
        },
        workload_template("rails"),
        workload_template("worker")
      ]
    end
    let(:existing_rails) do
      {
        "kind" => "workload",
        "name" => "rails",
        "status" => { "readyLatest" => true },
        "spec" => {
          "containers" => [
            { "name" => "rails", "image" => deployed_image }
          ]
        }
      }
    end
    let(:existing_workloads) { [existing_rails].compact }
    let(:applied_templates) { [] }

    def workload_template(name)
      {
        "kind" => "workload",
        "name" => name,
        "spec" => {
          "containers" => [
            { "name" => name, "image" => latest_image }
          ]
        }
      }
    end

    before do
      allow(TemplateParser).to receive(:new).with(command).and_return(parser)
      allow(parser).to receive(:template_filename) { |name| "#{__dir__}/../spec_helper.rb##{name}" }
      allow(parser).to receive(:parse).and_return(templates)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(match(/spec_helper\.rb#/)).and_return(true)
      allow(command).to receive(:cp).and_return(cp)
      allow(config).to receive(:[]).with(:app_workloads).and_return(app_workloads)
      allow(cp).to receive(:fetch_secret).with("test-review-123-pg").and_return({ "name" => "test-review-123-pg" })
      allow(cp).to receive_messages(
        fetch_workloads: { "items" => existing_workloads },
        fetch_workload: nil
      )
      allow(cp).to receive(:fetch_workload).with("rails").and_return(existing_rails)
      allow(cp).to receive(:apply_hash) do |template|
        applied_templates << Marshal.load(Marshal.dump(template))
        [{ kind: template.fetch("kind"), name: template.fetch("name") }]
      end
    end

    it "preserves deployed app images and existing secret resources" do
      command.call

      expect(applied_templates.map { |template| template["name"] })
        .to eq(%w[rails worker])
      expect(applied_templates.map { |template| template.dig("spec", "containers", 0, "image") })
        .to eq([deployed_image, deployed_image])
    end

    context "with bare app image references" do
      let(:latest_image) { "test-review-123:9_bad" }
      let(:deployed_image) { "test-review-123:8_good" }

      it "preserves the deployed image" do
        command.call

        expect(applied_templates.map { |template| template.dig("spec", "containers", 0, "image") })
          .to eq([deployed_image, deployed_image])
      end
    end

    context "when a configured workload was renamed" do
      let(:app_workloads) { %w[web] }
      let(:templates) { [workload_template("web")] }

      it "uses the removed workload's deployed app image as the safe fallback" do
        command.call

        expect(applied_templates.dig(0, "spec", "containers", 0, "image")).to eq(deployed_image)
      end
    end

    context "when existing workloads have different deployed app images" do
      let(:app_workloads) { %w[web] }
      let(:templates) { [workload_template("web")] }
      let(:existing_workloads) do
        [
          existing_rails,
          workload_template("worker").tap do |workload|
            workload["status"] = { "readyLatest" => true }
            workload.dig("spec", "containers", 0)["image"] =
              "/org/test-org/image/test-review-123:7_other"
          end
        ]
      end

      it "fails before applying an ambiguous fallback image" do
        expect { command.call }
          .to raise_error(/Cannot safely refresh app image for workload 'web'/)
        expect(applied_templates).to be_empty
      end
    end

    context "when equivalent deployed app images use bare and linked references" do
      let(:app_workloads) { %w[web] }
      let(:templates) { [workload_template("web")] }
      let(:existing_workloads) do
        [
          existing_rails,
          workload_template("worker").tap do |workload|
            workload["status"] = { "readyLatest" => true }
            workload.dig("spec", "containers", 0)["image"] = "test-review-123:8_good"
          end
        ]
      end

      it "uses the equivalent deployed image as the safe fallback" do
        command.call

        expect(applied_templates.dig(0, "spec", "containers", 0, "image")).to eq(deployed_image)
      end
    end

    context "when an existing runner workload uses the missing-image sentinel" do
      let(:app_workloads) { %w[rails-runner] }
      let(:templates) { [workload_template("rails-runner")] }
      let(:existing_workloads) do
        [
          existing_rails,
          workload_template("rails-runner").tap do |workload|
            workload["status"] = { "readyLatest" => true }
            workload.dig("spec", "containers", 0)["image"] =
              "test-review-123:#{Controlplane::NO_IMAGE_AVAILABLE}"
          end
        ]
      end

      it "ignores the sentinel when choosing the safe fallback" do
        command.call

        expect(applied_templates.dig(0, "spec", "containers", 0, "image")).to eq(deployed_image)
      end
    end

    context "when the matching workload's latest revision is not ready" do
      let(:app_workloads) { %w[worker] }
      let(:templates) { [workload_template("worker")] }
      let(:existing_workloads) do
        [
          existing_rails,
          workload_template("worker").tap do |workload|
            workload["status"] = { "readyLatest" => false }
            workload.dig("spec", "containers", 0)["image"] = latest_image
          end
        ]
      end

      it "uses a ready workload's deployed app image" do
        command.call

        expect(applied_templates.dig(0, "spec", "containers", 0, "image")).to eq(deployed_image)
      end
    end

    context "without a deployed app image" do
      let(:existing_rails) { nil }

      it "fails before applying templates" do
        expect { command.call }
          .to raise_error(/Cannot safely refresh app image for workload 'rails'/)
        expect(applied_templates).to be_empty
      end
    end

    context "when runtime preservation is requested for a missing app" do
      before do
        allow(cp).to receive(:fetch_workloads).and_return(nil)
        allow(cp).to receive(:fetch_gvc!).and_raise(
          "Can't find app 'test-review-123', please create it with 'cpflow setup-app -a test-review-123'."
        )
      end

      it "uses the established missing-app error" do
        expect { command.call }
          .to raise_error("Can't find app 'test-review-123', " \
                          "please create it with 'cpflow setup-app -a test-review-123'.")
        expect(cp).to have_received(:fetch_gvc!)
        expect(applied_templates).to be_empty
      end
    end

    context "without runtime preservation" do
      let(:options) { { yes: true, preserve_existing_runtime: false } }

      it "keeps ordinary template application behavior" do
        command.call

        expect(applied_templates.map { |template| template["name"] })
          .to eq(%w[test-review-123-pg rails worker])
        expect(applied_templates.drop(1).map { |template| template.dig("spec", "containers", 0, "image") })
          .to eq([latest_image, latest_image])
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
