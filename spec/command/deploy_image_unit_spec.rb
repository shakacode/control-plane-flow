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
end
