# frozen_string_literal: true

require "spec_helper"

RSpec.describe "README Heroku command mapping" do # rubocop:disable RSpec/DescribeClass
  let(:readme) { File.read(File.expand_path("../README.md", __dir__)) }
  let(:table_match) do
    readme.match(
      /## Mapping of Heroku Commands to `cpflow` and `cpln`\n\n(?<table>(?:\|.*\n)+)/
    )
  end
  let(:table) { table_match[:table] }

  it "does not leave placeholder mappings for Heroku commands" do
    expect(table_match).to be_truthy, "Could not locate Heroku mapping table in README.md"

    command_rows = table.lines.select { |line| line.start_with?("| [heroku ") }

    expect(command_rows).not_to be_empty

    placeholders = command_rows.select do |line|
      # Column indices after split("|"): 0=empty, 1=Heroku command, 2=cpflow mapping, 3=empty.
      line.split("|").map(&:strip).fetch(2, "") == "?"
    end

    expect(placeholders).to be_empty
  end
end
