# frozen_string_literal: true

# Inspired by https://github.com/rails/thor/wiki/Subcommands
class BaseSubCommand < Thor
  def self.banner(command, _namespace = nil, _subcommand = false) # rubocop:disable Style/OptionalBooleanParameter
    "#{basename} #{subcommand_prefix} #{command.usage}"
  end

  def self.subcommand_prefix
    name
      .gsub(/.*::/, "")
      .gsub(/^[A-Z]/) { |match| match[0].downcase }
      .gsub(/[A-Z]/) { |match| "-#{match[0].downcase}" }
  end
end
