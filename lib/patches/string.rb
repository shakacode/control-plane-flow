# frozen_string_literal: true

# rubocop:disable Style/OptionalBooleanParameter, Lint/UnderscorePrefixedVariableName
class String
  # Copied from Rails
  def indent(amount, indent_string = nil, indent_empty_lines = false)
    dup.tap { |_| _.indent!(amount, indent_string, indent_empty_lines) }
  end

  # Copied from Rails
  def indent!(amount, indent_string = nil, indent_empty_lines = false)
    indent_string = indent_string || self[/^[ \t]/] || " "
    re = indent_empty_lines ? /^/ : /^(?!$)/
    gsub!(re, indent_string * amount)
  end

  def unindent
    gsub(/^#{scan(/^[ \t]+(?=\S)/).min}/, "")
  end

  # Copied from Rails
  def underscore
    gsub("::", "/").gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').tr("-", "_").downcase
  end

  # Covers only simple cases and used for pluralizing controlplane template kinds (`gvc`, `secret`, `policy`, etc.)
  def pluralize
    return self if empty?
    return "#{self[...-1]}ies" if end_with?("y")

    "#{self}s"
  end
end
# rubocop:enable Style/OptionalBooleanParameter, Lint/UnderscorePrefixedVariableName
