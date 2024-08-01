# frozen_string_literal: true

require "spec_helper"

options_by_key_name = Command::Base.all_options_by_key_name
non_boolean_options_by_key_name = options_by_key_name
                                  .reject { |_, option| option[:params][:type] == :boolean }

describe Cpflow do
  it "has a version number" do
    expect(Cpflow::VERSION).not_to be_nil
  end

  non_boolean_options_by_key_name.each do |option_key_name, option|
    it "raises error if no value is provided for '#{option_key_name}' option" do
      result = run_cpflow_command("test", option_key_name)

      expect(result[:status]).not_to eq(0)
      expect(result[:stderr]).to include("No value provided for option --#{option[:name].to_s.tr('_', '-')}")
    end
  end

  it "handles subcommands correctly" do
    result = run_cpflow_command("--help")

    expect(result[:status]).to eq(0)

    # Temporary solution, will be fixed with https://github.com/rails/thor/issues/742
    basename = Cpflow::Cli.send(:basename)

    Cpflow::Cli.subcommand_names.each do |subcommand|
      expect(result[:stdout]).to include("#{basename} #{subcommand}")

      subcommand_result = run_cpflow_command(subcommand, "--help")

      expect(subcommand_result[:status]).to eq(0)
      expect(subcommand_result[:stdout]).to include("#{basename} #{subcommand} help [COMMAND]")
    end
  end
end
