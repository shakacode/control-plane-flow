# frozen_string_literal: true

RSpec.describe "README Heroku command mapping" do # rubocop:disable RSpec/DescribeClass
  let(:readme) { File.read("README.md") }
  let(:table) do
    readme.match(
      /## Mapping of Heroku Commands to `cpflow` and `cpln`\n\n(?<table>(?:\|.*\n)+)/
    )[:table]
  end

  it "does not leave placeholder mappings for Heroku commands" do
    command_rows = table.lines.select { |line| line.start_with?("| [heroku ") }

    expect(command_rows).not_to be_empty

    placeholders = command_rows.select do |line|
      line.split("|").map(&:strip).fetch(2) == "?"
    end

    expect(placeholders).to be_empty
  end
end
