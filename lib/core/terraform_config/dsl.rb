# frozen_string_literal: true

module TerraformConfig
  module Dsl
    extend Forwardable

    REFERENCE_PATTERN = /^(var|locals|cpln_\w+)\./.freeze

    def_delegators :current_context, :put, :output

    def block(name, *labels)
      switch_context do
        put("#{block_declaration(name, labels)} {\n")
        yield
        put("}\n")
      end

      # There is extra indent for whole output that needs to be removed
      output.unindent
    end

    def argument(name, value, optional: false)
      return if value.nil? && optional

      content =
        if value.is_a?(Hash)
          "{\n#{value.map { |n, v| "#{n} = #{tf_value(v)}" }.join("\n").indent(2)}\n}\n"
        else
          "#{tf_value(value)}\n"
        end

      put("#{name} = #{content}", indent: 2)
    end

    private

    def tf_value(value, heredoc_delimiter: "EOF", multiline_indent: 2)
      value = value.to_s if value.is_a?(Symbol)

      return value unless value.is_a?(String)
      return value if expression?(value)
      return "\"#{value}\"" unless value.include?("\n")

      "#{heredoc_delimiter}\n#{value.indent(multiline_indent)}\n#{heredoc_delimiter}"
    end

    def expression?(value)
      value.match?(REFERENCE_PATTERN)
    end

    def block_declaration(name, labels)
      result = name.to_s
      return result unless labels.any?

      result + " #{labels.map { |label| tf_value(label) }.join(' ')}"
    end

    class Context
      attr_accessor :output

      def initialize
        @output = ""
      end

      def put(content, indent: 0)
        @output += content.to_s.indent(indent)
      end
    end

    def switch_context
      old_context = current_context
      @current_context = Context.new
      yield
    ensure
      old_context.put(current_context.output, indent: 2)
      @current_context = old_context
    end

    def current_context
      @current_context ||= Context.new
    end
  end
end
