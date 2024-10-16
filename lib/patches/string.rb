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

  def pluralize
    return self if empty?

    if end_with?("ies")
      self
    elsif end_with?("s", "x", "z", "ch", "sh")
      end_with?("es") ? self : "#{self}es"
    elsif end_with?("y")
      "#{self[...-1]}ies"
    else
      end_with?("s") ? self : "#{self}s"
    end
  end
end
# rubocop:enable Style/OptionalBooleanParameter, Lint/UnderscorePrefixedVariableName
