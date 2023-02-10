# frozen_string_literal: true

commands = Command::Base.all_commands
options_key_name = Command::Base.all_options_key_name

describe Cpl do
  it "has a version number" do
    expect(Cpl::VERSION).not_to be_nil
  end

  commands.each do |_command_key, command_class|
    # Temporary tests to ensure nothing breaks when converting to Thor
    it "calls '#{command_class.name}' for '#{command_class::NAME}' command" do # rubocop:disable RSpec/ExampleLength
      args = command_class::REQUIRES_ARGS ? ["test"] : []
      command_class::OPTIONS.each do |option|
        if option[:params][:required]
          args.push("--#{option[:name]}")
          args.push("whatever")
        end
      end

      allow_any_instance_of(Config).to receive(:find_app_config_file).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(command_class).to receive(:call) # rubocop:disable RSpec/AnyInstance

      Cpl::Cli.start([command_class::NAME, *args])
    end
  end

  options_key_name.each do |option_key, option_name|
    # Temporary tests to ensure nothing breaks when converting to Thor
    it "parses '#{option_key}' option" do # rubocop:disable RSpec/ExampleLength
      option_value = "whatever"

      args = [option_key, option_value]

      allow(Config).to receive(:new).with([], { option_name.to_sym => option_value }).and_call_original

      allow_any_instance_of(Config).to receive(:find_app_config_file).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(Command::Test).to receive(:call) # rubocop:disable RSpec/AnyInstance

      Cpl::Cli.start(["test", *args])
    end
  end
end
