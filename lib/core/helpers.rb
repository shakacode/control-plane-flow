# frozen_string_literal: true

require "securerandom"

module Helpers
  module_function

  def strip_str_and_validate(str)
    return str if str.nil?

    str = str.strip
    str.empty? ? nil : str
  end

  def random_four_digits
    SecureRandom.random_number(1000..9999)
  end

  def normalize_command_name(name)
    name.to_s.tr("_", "-")
  end

  def normalize_option_name(name)
    "--#{name.to_s.tr('_', '-')}"
  end
end
