# frozen_string_literal: true

require "spec_helper"

describe Terraform::Config::Base do
  let(:config) { described_class.new }

  describe "#to_tf" do
    subject(:to_tf) { config.to_tf }

    it "raises NotImplementedError" do
      expect { to_tf }.to raise_error(NotImplementedError)
    end
  end
end
