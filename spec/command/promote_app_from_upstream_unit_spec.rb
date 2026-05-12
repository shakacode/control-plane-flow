# frozen_string_literal: true

require "spec_helper"

describe Command::PromoteAppFromUpstream do
  describe "#deploy_image" do
    let(:command) { described_class.new(config) }
    let(:config) do
      instance_double(
        Config,
        app: "test-app",
        current: current,
        options: options,
        use_digest_image_ref?: use_digest_image_ref
      )
    end
    let(:current) { {} }
    let(:options) { {} }
    let(:use_digest_image_ref) { false }

    before do
      allow(command).to receive(:run_cpflow_command)
    end

    it "omits digest flags when digest mode is unset" do
      command.send(:deploy_image)

      expect(command).to have_received(:run_cpflow_command).with("deploy-image", "-a", "test-app")
    end

    context "when digest mode is explicitly disabled" do
      let(:options) { { use_digest_image_ref: false } }

      it "forwards the explicit disable flag" do
        command.send(:deploy_image)

        expect(command)
          .to have_received(:run_cpflow_command)
          .with("deploy-image", "-a", "test-app", "--no-use-digest-image-ref")
      end
    end

    context "when digest mode resolves to true" do
      let(:use_digest_image_ref) { true }

      it "forwards the enable flag" do
        command.send(:deploy_image)

        expect(command)
          .to have_received(:run_cpflow_command)
          .with("deploy-image", "-a", "test-app", "--use-digest-image-ref")
      end
    end

    context "when the current app config has a release script" do
      let(:current) { { release_script: "release.sh" } }

      it "forwards the release phase flag" do
        command.send(:deploy_image)

        expect(command)
          .to have_received(:run_cpflow_command)
          .with("deploy-image", "-a", "test-app", "--run-release-phase")
      end
    end

    context "when the current app config is missing" do
      let(:current) { nil }

      it "still invokes deploy-image without release phase" do
        command.send(:deploy_image)

        expect(command).to have_received(:run_cpflow_command).with("deploy-image", "-a", "test-app")
      end
    end
  end
end
