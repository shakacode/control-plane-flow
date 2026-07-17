# frozen_string_literal: true

require "spec_helper"

describe Command::StagingBranchValidation do
  let(:harness_class) do
    Class.new do
      include Command::StagingBranchValidation

      attr_reader :config

      def initialize(config)
        @config = config
      end
    end
  end
  let(:branch_option) { nil }
  let(:config) { instance_double(Config, options: { staging_branch: branch_option }) }
  let(:harness) { harness_class.new(config) }

  describe "#staging_branch" do
    context "when the option is not given" do
      it "returns nil" do
        expect(harness.send(:staging_branch)).to be_nil
      end
    end

    context "when the option is blank" do
      let(:branch_option) { "   " }

      it "returns nil" do
        expect(harness.send(:staging_branch)).to be_nil
      end
    end

    context "when the option is a valid branch name" do
      let(:branch_option) { " develop " }

      it "returns the stripped branch name" do
        expect(harness.send(:staging_branch)).to eq("develop")
      end
    end

    context "when the option is an invalid branch name" do
      let(:branch_option) { "bad..branch" }

      it "aborts with an explanatory message" do
        allow(Shell).to receive(:abort).and_raise(SystemExit.new(ExitCode::ERROR_DEFAULT))

        expect { harness.send(:staging_branch) }.to raise_error(SystemExit)
        expect(Shell).to have_received(:abort).with(/Invalid --staging-branch value: "bad\.\.branch"/)
      end
    end
  end

  describe "#valid_staging_branch?" do
    def valid?(branch)
      harness.send(:valid_staging_branch?, branch)
    end

    it "accepts common git branch names" do
      %w[
        main
        develop
        feature/add-login
        release-1.2.3
        user@host
        hotfix/v1.0.0
        a.b.c
        with_underscore
      ].each do |branch|
        expect(valid?(branch)).to be(true), "expected #{branch.inspect} to be valid"
      end
    end

    it "rejects branch names with disallowed characters" do
      invalid_branches = ["has space", "has~tilde", "has^caret", "has:colon", "has?question", "has*star", ""]
      invalid_branches.each do |branch|
        expect(valid?(branch)).to be(false), "expected #{branch.inspect} to be invalid"
      end
    end

    it "rejects branch names with an invalid shape" do
      %w[
        -leading-dash
        /leading-slash
        .leading-dot
        trailing-slash/
        trailing-dot.
        double..dot
        reflog@{1}
      ].each do |branch|
        expect(valid?(branch)).to be(false), "expected #{branch.inspect} to be invalid"
      end
    end

    it "rejects branch names with invalid path components" do
      %w[
        feature//double-slash
        feature/.hidden
        feature/locked.lock
        locked.lock/feature
      ].each do |branch|
        expect(valid?(branch)).to be(false), "expected #{branch.inspect} to be invalid"
      end
    end
  end
end
