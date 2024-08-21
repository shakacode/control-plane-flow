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
        argument :local_var, "locals.local_var"
        argument :input_var, "var.input_var"
        argument :non_expression_var, "non_expression_value"
      end
    end

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          test {
            local_var = locals.local_var
            input_var = var.input_var
            non_expression_var = "non_expression_value"
          }
        EXPECTED
      )
    end
  end
end
