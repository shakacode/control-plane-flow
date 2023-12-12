# frozen_string_literal: true

module Helpers
  def strip_str_and_validate(str)
    return str if str.nil?

    str = str.strip
    str.empty? ? nil : str
  end
end
