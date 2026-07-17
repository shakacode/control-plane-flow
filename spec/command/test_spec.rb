# frozen_string_literal: true

require "spec_helper"

describe Command::Test do
  it "is hidden from the command list" do
    expect(described_class::HIDE).to be(true)
  end

  it "skips validations" do
    expect(described_class::VALIDATIONS).to be_empty
  end

  it "accepts every available option" do
    option_names = described_class::OPTIONS.map { |option| option[:name] }

    expect(option_names).to match_array(Command::Base.all_options.map { |option| option[:name] })
  end

  describe "#call" do
    it "does nothing by default" do
      command = described_class.new(instance_double(Config))

      expect(command.call).to be_nil
    end
  end
end
