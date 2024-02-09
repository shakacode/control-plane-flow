# frozen_string_literal: true

commands = Command::Base.all_commands
options_by_key_name = Command::Base.all_options_by_key_name

describe Cpl do
  it "has a version number" do
    expect(Cpl::VERSION).not_to be_nil
  end

  commands.each do |_command_key, command_class|
    # Temporary tests to ensure nothing breaks when converting to Thor
    it "calls '#{command_class.name}' for '#{command_class::NAME}' command" do
      args = command_class::REQUIRES_ARGS ? ["test"] : []
      command_class::OPTIONS.each do |option|
        if option[:params][:required]
          args.push("--#{option[:name]}")
          args.push("my-app-staging")
        end
      end

      allow_any_instance_of(Config).to receive(:config_file_path).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(command_class).to receive(:call) # rubocop:disable RSpec/AnyInstance

      Cpl::Cli.start([command_class::NAME, *args])
    end
  end

  options_by_key_name.each do |option_key_name, option|
    # Temporary tests to ensure nothing breaks when converting to Thor
    it "parses '#{option_key_name}' option" do
      if option[:params][:type] == :boolean
        option_value = true
        args = [option_key_name]
      else
        option_value = "my-app-staging"
        args = [option_key_name, option_value]
      end

      allow(Config).to receive(:new)
        .with([], hash_including(option[:name].to_sym => option_value), [])
        .and_call_original

      allow_any_instance_of(Config).to receive(:config_file_path).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(Command::Test).to receive(:call) # rubocop:disable RSpec/AnyInstance

      Cpl::Cli.start(["test", *args])
    end
  end
end
