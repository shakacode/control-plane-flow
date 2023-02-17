# frozen_string_literal: true

commands = Command::Base.all_commands
options = {
  "-a": "app",
  "--app": "app",
  "-c": "commit",
  "--commit": "commit",
  "-i": "image",
  "--image": "image",
  "-w": "workload",
  "--workload": "workload"
}

describe Cpl do
  it "has a version number" do
    expect(Cpl::VERSION).not_to be_nil
  end

  commands.each do |command_name, command_class|
    # Temporary tests to ensure nothing breaks when converting to Thor
    it "calls '#{command_class.name}' for '#{command_name}' command" do # rubocop:disable RSpec/ExampleLength
      stub_const("ARGV", [command_name.to_s])

      allow_any_instance_of(Config).to receive(:find_app_config_file).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance

      config = Config.new
      command_instance = command_class.new(config)

      allow(command_instance).to receive(:call)
      allow(command_class).to receive(:new).and_return(command_instance)

      Cpl::Cli.new

      expect(command_instance).to have_received(:call)
    end
  end

  options.each do |option_key, option_name|
    # Temporary tests to ensure nothing breaks when converting to Thor
    it "parses '#{option_key}' option" do
      option_value = "whatever"
      stub_const("ARGV", ["test", option_key, option_value])

      allow_any_instance_of(Config).to receive(:find_app_config_file).and_return("spec/fixtures/config.yml") # rubocop:disable RSpec/AnyInstance

      config = Config.new

      expect(config.options).to eq({ option_name.to_sym => option_value })
    end
  end
end
