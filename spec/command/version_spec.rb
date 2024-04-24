# frozen_string_literal: true

require "spec_helper"

describe Command::Version do
  it "displays version" do
    result = run_cpl_command("version")

    expect(result[:status]).to eq(0)
    expect(result[:stdout]).to include(Cpl::VERSION)
  end
end
