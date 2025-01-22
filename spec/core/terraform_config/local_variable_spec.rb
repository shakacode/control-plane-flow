# frozen_string_literal: true

require "spec_helper"

describe TerraformConfig::LocalVariable do
  let(:config) { described_class.new(**variables) }

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

  describe "#initialize" do
    context "when variables are empty" do
      let(:variables) { {} }

      it "raises an ArgumentError" do
        expect { config }.to raise_error(ArgumentError, "Variables cannot be empty")
      end
    end
  end

  describe "#to_tf" do
    subject(:generated) { config.to_tf }

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

  it_behaves_like "unimportable terraform resource"
end
