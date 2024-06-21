# frozen_string_literal: true

require "spec_helper"

describe Command::Version do
  it "displays version" do
    result = run_cpflow_command("version")

    expect(result[:status]).to eq(0)
    expect(result[:stdout]).to include(Cpflow::VERSION)
  end
end
