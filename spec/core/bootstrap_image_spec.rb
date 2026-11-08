# frozen_string_literal: true

require "spec_helper"

RSpec.describe BootstrapImage do
  let(:image) { "example-pr-123:12_#{'a' * 40}" }
  let(:options) { { bootstrap_image: image } }
  let(:config) { instance_double(Config, app: "example-pr-123", org: "test-org", options: options) }
  let(:cp) { instance_double(Controlplane) }

  before do
    allow(cp).to receive(:fetch_image_details).with(image).and_return("name" => image)
  end

  it "accepts a registry-backed image from the current app" do
    expect(described_class.resolve(config, cp, preserving: true)).to eq(image)
  end

  it "accepts the same org's fully qualified image reference" do
    reference = "/org/test-org/image/#{image}"
    options[:bootstrap_image] = reference
    expect(described_class.resolve(config, cp, preserving: true)).to eq(reference)
  end

  it "does nothing without explicit opt-in" do
    options.clear
    expect(described_class.resolve(config, cp, preserving: true)).to be_nil
    expect(cp).not_to have_received(:fetch_image_details)
  end

  it "rejects bootstrap outside preservation before contacting the registry" do
    expect { described_class.resolve(config, cp, preserving: false) }.to raise_error(/requires runtime preservation/)
    expect(cp).not_to have_received(:fetch_image_details)
  end

  it "rejects a short commit, foreign app, foreign org, or digest reference" do
    ["example-pr-123:12_abc123", "other-app:12_#{'a' * 40}", "/org/other-org/image/#{image}",
     "#{image}@sha256:#{'b' * 64}"].each do |reference|
      options[:bootstrap_image] = reference
      expect { described_class.resolve(config, cp, preserving: true) }.to raise_error(/must belong/)
    end
    expect(cp).not_to have_received(:fetch_image_details)
  end

  it "rejects registry metadata for a different image" do
    allow(cp).to receive(:fetch_image_details).with(image).and_return("name" => "other-app:12")
    expect { described_class.resolve(config, cp, preserving: true) }.to raise_error(/does not exist/)
  end
end
