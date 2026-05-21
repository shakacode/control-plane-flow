# frozen_string_literal: true

require "spec_helper"

describe Command::DeployImage do
  describe "#resolve_image_to_deploy" do
    def build_command(image_details:, use_digest_image_ref: true)
      image = "test-app:1"
      config = instance_double(Config, app: "test-app", org: "test-org", use_digest_image_ref?: use_digest_image_ref)
      cp = instance_double(Controlplane, latest_image: image, fetch_image_details: image_details)

      command = described_class.new(config)
      allow(command).to receive(:cp).and_return(cp)
      command
    end

    context "when digest mode is enabled" do
      it "returns the latest image with its digest reference" do
        digest = "sha256:#{'a' * 64}"
        command = build_command(image_details: { "digest" => digest })

        expect(command.send(:resolve_image_to_deploy)).to eq("test-app:1@#{digest}")
      end
    end

    context "when digest mode is disabled" do
      it "returns the latest image without validating the digest" do
        command = build_command(
          image_details: { "digest" => "sha512:#{'a' * 128}" },
          use_digest_image_ref: false
        )

        expect(command.send(:resolve_image_to_deploy)).to eq("test-app:1")
      end
    end

    context "when the image does not exist" do
      it "raises the image not found error" do
        command = build_command(image_details: nil)

        expect { command.send(:resolve_image_to_deploy) }
          .to raise_error(/Image 'test-app:1' does not exist in the Docker repository/)
      end
    end

    context "when the image has no digest" do
      it "raises a digest availability error" do
        command = build_command(image_details: { "digest" => nil })

        expect { command.send(:resolve_image_to_deploy) }
          .to raise_error("Image 'test-app:1' does not have a digest available.")
      end
    end

    context "when the image has an empty digest" do
      it "raises a digest availability error" do
        command = build_command(image_details: { "digest" => "" })

        expect { command.send(:resolve_image_to_deploy) }
          .to raise_error("Image 'test-app:1' does not have a digest available.")
      end
    end

    context "when the image has an invalid digest format" do
      it "raises a digest format error" do
        command = build_command(image_details: { "digest" => "sha512:#{'a' * 128}" })

        expect { command.send(:resolve_image_to_deploy) }
          .to raise_error("Unexpected digest format for image 'test-app:1'.")
      end
    end
  end

  describe "#call" do
    let(:config) do
      instance_double(
        Config,
        app: "test-app",
        org: "test-org",
        options: { run_release_phase: false },
        use_digest_image_ref?: false
      )
    end
    let(:cp) { instance_double(Controlplane) }
    let(:command) { described_class.new(config) }
    let(:workload_data) do
      {
        "name" => "frontend",
        "spec" => {
          "containers" => [
            { "name" => "rails", "image" => "/org/test-org/image/test-app:1" }
          ]
        },
        "status" => { "endpoint" => "https://frontend-test.cpln.app" }
      }
    end

    before do
      allow(config).to receive(:[]).with(:app_workloads).and_return(["frontend"])
      allow(cp).to receive(:fetch_workload!).with("frontend").and_return(workload_data)
      allow(cp).to receive_messages(
        latest_image: "test-app:1",
        fetch_image_details: { "digest" => "sha256:#{'a' * 64}" },
        workload_set_image_ref: true
      )
      allow(command).to receive(:cp).and_return(cp)
      allow(Resolv).to receive(:getaddress).and_return("1.2.3.4")
    end

    it "shows the workload name in the deploy step message, not the container name" do
      expect { command.call }.to output(/Deploying image 'test-app:1' for workload 'frontend'/).to_stderr
    end

    it "lists the workload name in the deployed endpoints section, not the container name" do
      expect { command.call }.to output(%r{- frontend: https://frontend-test\.cpln\.app}).to_stderr
    end

    it "uses the container name for the API call that updates the image ref" do
      command.call

      expect(cp).to have_received(:workload_set_image_ref)
        .with("frontend", container: "rails", image: "test-app:1")
    end

    context "when a workload has multiple containers matching the app image" do
      let(:workload_data) do
        {
          "name" => "frontend",
          "spec" => {
            "containers" => [
              { "name" => "rails", "image" => "/org/test-org/image/test-app:1" },
              { "name" => "rails-sidecar", "image" => "/org/test-org/image/test-app:1" }
            ]
          },
          "status" => { "endpoint" => "https://frontend-test.cpln.app" }
        }
      end

      it "deploys only the first matching container to avoid duplicate steps per workload" do
        command.call

        expect(cp).to have_received(:workload_set_image_ref)
          .with("frontend", container: "rails", image: "test-app:1").once
        expect(cp).not_to have_received(:workload_set_image_ref)
          .with("frontend", container: "rails-sidecar", image: "test-app:1")
      end
    end
  end
end
