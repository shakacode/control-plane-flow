# frozen_string_literal: true

# TODO: Fix indentations
module Terraform
  module Config
    class Base
      def to_tf
        raise NotImplementedError
      end

      private

      def block(name, *labels)
        switch_context do
          context.put "#{name} #{labels.map { |label| tf_value(label) }.join(' ')} {\n"
          yield
          context.put "}\n"
        end

        context.output
      end

      def argument(name, value, optional: false)
        return if value.nil? && optional

        content =
          if value.is_a?(Hash)
            "{\n#{value.map { |n, v| "#{n} = #{tf_value(v)}\n".indent(context.indent) }.join("\n")}\n}\n"
          else
            "#{tf_value(value)}\n"
          end

        context.put "#{name} = #{content}".indent(context.indent)
      end

      def switch_context
        old_context = context
        @context = Context.new(indent: old_context.indent + 2)
        yield
      ensure
        old_context.put(context.output)
        @context = old_context
      end

      def context
        @context ||= Context.new(indent: 0)
      end

      def tf_value(value)
        value = value.to_s if value.is_a?(Symbol)

        case value
        when String
          expression?(value) ? value : "\"#{value}\""
        else
          value
        end
      end

      def expression?(value)
        value.start_with?("var.") || value.start_with?("locals.")
      end

      class Context
        attr_accessor :output, :indent

        def initialize(indent: 0)
          @output = ""
          @indent = indent
        end

        def put(content)
          @output += content.indent(indent)
        end
      end
    end
  end
end
