# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::LocalVariable do
  let(:config) { described_class.new(**variables) }

  describe "#initialize" do
    context "when variables are empty" do
      let(:variables) { {} }

      it "raises an ArgumentError" do
        expect { config }.to raise_error(ArgumentError, "Variables cannot be empty")
      end
    end

    context "when variable names are invalid" do
      let(:variables) do
        {
          valid_var: 1,
          "invalid-var" => 2, # Invalid due to hyphen
          another_invalid_var: 3
        }
      end

      it "raises an ArgumentError with invalid names" do
        expect { config }.to raise_error(ArgumentError, /Invalid variable names: invalid-var/)
      end
    end

    context "when variable names are valid" do
      let(:variables) do
        {
          valid_var: 1,
          another_valid_var: 2
        }
      end

      it "initializes without error" do
        expect { config }.not_to raise_error
      end
    end
  end

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

    let(:variables) do
      {
        hash_var: {
          key1: "value1",
          key2: "value2"
        },
        int_var: 1,
        string_var: "string",
        input_var: "var.input_var",
        local_var: "local.local_var"
      }
    end

    it "generates correct config" do
      expect(generated).to eq(
        <<~EXPECTED
          locals {
            hash_var = {
              key1 = "value1"
              key2 = "value2"
            }
            int_var = 1
            string_var = "string"
            input_var = var.input_var
            local_var = local.local_var
          }
        EXPECTED
      )
    end
  end
end
