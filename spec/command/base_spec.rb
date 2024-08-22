# frozen_string_literal: true

require "spec_helper"

describe Command::Base do
  let(:config) { instance_double(Command::Config) }
  let(:command) { described_class.new(config) }

  around do |example|
    suppress_output { example.run }
  end

  describe "#step" do
    let(:message) { "test message" }

    context "with retry_on_failure: true" do
      let(:options) { { retry_on_failure: true, wait: 0 } }

      it "retries block until success" do
        run_count = 0

        command.step(message, **options) do
          run_count += 1
          true if run_count == 3
        end

        expect(run_count).to eq(3)
      end

      context "with max_retry_count option" do
        let(:options) { super().merge(max_retry_count: 1) }

        it "retries block specified times" do
          run_count = 0

          command.step(message, **options) do
            run_count += 1
            false
          end

          expect(run_count).to eq(1 + 1) # 1 run and 1 retry after fail
        end
      end
    end

    context "with retry_on_failure: false" do
      let(:options) { { retry_on_failure: false } }

      it "does not retry block" do
        run_count = 0

        command.step(message, **options) do
          run_count += 1
          false
        end

        expect(run_count).to eq(1)
      end
    end
  end
end
