# frozen_string_literal: true

require "spec_helper"

describe Command::Terraform::Import do
  let(:import_command) { described_class.new(config) }

  let(:config) { instance_double(Config, app: "test-app", apps: { "test-app" => {} }) }
  let(:terraform_dir) { Pathname.new("/fake/terraform/dir") }

  before do
    allow(import_command).to receive(:terraform_dir).and_return(terraform_dir)
  end

  describe "#call" do
    subject(:call) { import_command.call }

    before do
      allow(import_command).to receive(:resources).and_return(
        [
          { address: "cpln_gvc.test-app", id: "test-app" },
          { address: "module.main.cpln_workload.workload", id: "test-app:main" }
        ]
      )
      allow(import_command).to receive(:run_terraform_init)
      allow(import_command).to receive(:run_terraform_import)
    end

    it "initializes terraform and imports resources" do
      expect(Dir).to receive(:chdir).with(terraform_dir.join(config.app)).and_yield # rubocop:disable RSpec/MessageSpies

      call

      expect(import_command).to have_received(:run_terraform_init)
      expect(import_command).to have_received(:run_terraform_import).with("cpln_gvc.test-app", "test-app")
      expect(import_command).to have_received(:run_terraform_import).with(
        "module.main.cpln_workload.workload",
        "test-app:main"
      )
    end
  end

  describe "#run_terraform_init" do
    subject(:terraform_init) { import_command.send(:run_terraform_init) }

    before do
      allow(Shell).to receive(:info)
      allow(Shell).to receive(:abort)
    end

    context "when initialization succeeds" do
      before do
        stub_terraform_init_with(true, "Terraform initialized")
      end

      it "logs success message" do
        terraform_init

        expect(Shell).to have_received(:info).with("Terraform initialized")
      end
    end

    context "when initialization fails" do
      before do
        stub_terraform_init_with(false, "Initialization failed")
      end

      it "aborts with error message" do
        terraform_init

        expect(Shell).to have_received(:abort).with("Failed to initialize terraform - Initialization failed")
      end
    end

    def stub_terraform_init_with(success, output)
      allow(Shell).to receive(:cmd).with("terraform", "init", capture_stderr: true).and_return(
        success: success, output: output
      )
    end
  end

  describe "#resources" do
    before do
      allow(import_command).to receive(:tf_configs).and_return(
        [
          verified_double(TerraformConfig::Gvc, importable?: true, reference: "cpln_gvc.app", name: "app"),
          verified_double(
            TerraformConfig::Workload,
            importable?: true,
            reference: "module.main.cpln_workload.workload",
            name: "main"
          ),
          verified_double(TerraformConfig::LocalVariable, importable?: false)
        ]
      )
    end

    it "returns only importable resources with correct format" do
      expect(import_command.send(:resources)).to contain_exactly(
        { address: "cpln_gvc.app", id: "app" },
        { address: "module.main.cpln_workload.workload", id: "test-app:main" }
      )
    end
  end

  describe "#run_terraform_import" do
    subject(:terraform_import) { import_command.send(:run_terraform_import, resource_address, resource_id) }

    let(:resource_address) { "resource_address" }
    let(:resource_id) { "resource_id" }

    before do
      allow(Shell).to receive(:cmd).and_call_original
      allow(Shell).to receive(:info)
      allow(Shell).to receive(:abort)
    end

    context "when import succeeds" do
      before do
        stub_terraform_import_with(true, "Import successful")
      end

      it "logs the success message" do
        terraform_import

        expect(Shell).to have_received(:info).with("Import successful")
      end
    end

    context "when import fails" do
      before do
        stub_terraform_import_with(false, "Import failed")
      end

      it "logs error" do
        terraform_import

        expect(Shell).to have_received(:info).with("Import failed")
      end
    end

    def stub_terraform_import_with(success, output)
      allow(Shell).to receive(:cmd)
        .with("terraform", "import", resource_address, resource_id, capture_stderr: true)
        .and_return(success: success, output: output)
    end
  end
end
