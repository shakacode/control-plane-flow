# frozen_string_literal: true

RSpec.shared_examples_for "unimportable terraform resource" do
  describe "#importable?" do
    subject { config.importable? }

    it { is_expected.to be(false) }
  end

  describe "#reference" do
    subject { config.reference }

    it { is_expected.to be_nil }
  end
end

RSpec.shared_examples_for "importable terraform resource" do |reference:|
  describe "#importable?" do
    subject { config.importable? }

    it { is_expected.to be(true) }
  end

  describe "#reference" do
    subject { config.reference }

    it { is_expected.to eq(reference) }
  end
end
