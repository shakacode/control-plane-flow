# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::Dsl do
  include described_class

  context "with simple config" do
    subject(:generated) do
      block :block_name do # rubocop:disable Lint/EmptyBlock
      end
    end

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          block_name {
          }
        EXPECTED
      )
    end
  end

  context "when block has arguments" do
    subject(:generated) do
      block :block_name, :label1, "label2" do # rubocop:disable Lint/EmptyBlock
      end
    end

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          block_name "label1" "label2" {
          }
        EXPECTED
      )
    end
  end

  context "with multiple blocks" do
    subject(:generated) do
      block :a do
        block :b do
          block :c do
            block :d do # rubocop:disable Lint/EmptyBlock
            end
          end
        end
      end
    end

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          a {
            b {
              c {
                d {
                }
              }
            }
          }
        EXPECTED
      )
    end
  end

  context "with blocks and simple arguments" do
    subject(:generated) do
      block :a do
        argument :a, 0

        block :b do
          argument :b, 1

          block :c do
            argument :c, 2

            block :d do
              argument :d, 3
            end
          end
        end
      end
    end

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          a {
            a = 0
            b {
              b = 1
              c {
                c = 2
                d {
                  d = 3
                }
              }
            }
          }
        EXPECTED
      )
    end
  end

  context "with hash argument" do
    subject(:generated) do
      block :a do
        argument :hash, { arg1: "value1", arg2: "value2" }
      end
    end

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          a {
            hash = {
              arg1 = "value1"
              arg2 = "value2"
            }
          }
        EXPECTED
      )
    end
  end

  context "when argument's value is an expression" do
    subject(:generated) do
      block :test do
        argument :local_var, "local.local_var"
        argument :input_var, "var.input_var"
        argument :non_expression_var, "non_expression_value"
      end
    end

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          test {
            local_var = local.local_var
            input_var = var.input_var
            non_expression_var = "non_expression_value"
          }
        EXPECTED
      )
    end
  end

  context "with optional arguments" do
    subject(:generated) do
      block :optional_test do
        argument :optional_arg, nil, optional: true
        argument :required_arg, "value"
      end
    end

    it "generates correct config without optional argument" do
      expect(generated).to eq(
        <<~EXPECTED
          optional_test {
            required_arg = "value"
          }
        EXPECTED
      )
    end
  end

  context "with raw hash argument" do
    subject(:generated) do
      block :raw_hash_test do
        argument :raw_hash_argument,
                 {
                   non_expression_var: "non_expression_value",
                   input_var: "var.input_var",
                   local_var: "local.local_var"
                 },
                 raw: true
      end
    end

    it "generates correct config with raw hash argument" do
      expect(generated).to eq(
        <<~EXPECTED
          raw_hash_test {
            raw_hash_argument = {
              non_expression_var: "non_expression_value"
              input_var: var.input_var
              local_var: local.local_var
            }
          }
        EXPECTED
      )
    end
  end
end
