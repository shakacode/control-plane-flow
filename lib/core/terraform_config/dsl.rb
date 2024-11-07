# frozen_string_literal: true

module TerraformConfig
  module Dsl
    extend Forwardable

    EXPRESSION_PATTERN = /(var|local|cpln_\w+)\./.freeze

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

    def argument(name, value, optional: false, raw: false)
      return if value.nil? && optional

      content =
        if value.is_a?(Hash)
          operator = raw ? ": " : " = "
          "{\n#{value.map { |n, v| "#{n}#{operator}#{tf_value(v)}" }.join("\n").indent(2)}\n}\n"
        else
          "#{tf_value(value)}\n"
        end

      put("#{name} = #{content}", indent: 2)
    end

    private

    def tf_value(value)
      value = value.to_s if value.is_a?(Symbol)

      case value
      when String
        tf_string_value(value)
      when Hash
        tf_hash_value(value)
      else
        value
      end
    end

    def tf_string_value(value)
      return value if expression?(value)
      return "\"#{value}\"" unless value.include?("\n")

      "EOF\n#{value.indent(2)}\nEOF"
    end

    def tf_hash_value(value)
      JSON.pretty_generate(value.crush)
          .gsub(/"(\w+)":/) { "#{::Regexp.last_match(1)}:" } # remove quotes from keys
          .gsub(/("#{EXPRESSION_PATTERN}.*")/) { ::Regexp.last_match(1)[1...-1] } # remove quotes from expression values
    end

    def expression?(value)
      value.match?(/^#{EXPRESSION_PATTERN}/)
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
