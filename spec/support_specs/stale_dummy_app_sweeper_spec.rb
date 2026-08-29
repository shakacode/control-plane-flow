# frozen_string_literal: true

require "spec_helper"

describe StaleDummyAppSweeper do
  subject(:sweep) { described_class.sweep(api: api, now: now, output: output) }

  let(:api) { instance_double(ControlplaneApi) }
  let(:output) { StringIO.new }
  let(:gvcs) { [] }

  before do
    allow(CommandHelpers).to receive_messages(dummy_test_org: org,
                                              dummy_test_app_global_identifier: current_identifier)
    allow(api).to receive(:gvc_list).with(org: org).and_return({ "items" => gvcs })
    allow(api).to receive(:gvc_delete)
    allow(api).to receive(:list_volumesets).and_return({ "items" => [] })
    allow(api).to receive(:delete_volumeset)
    allow(api).to receive(:delete_workload)
  end

  def org
    "org-for-tests"
  end

  def current_identifier
    "aaaa"
  end

  def now
    Time.utc(2026, 8, 28, 12, 0, 0)
  end

  # Comfortably past `MIN_AGE_SECONDS`, matching the weeks-old leaks this exists for.
  def six_weeks_ago
    now - (42 * 24 * 60 * 60)
  end

  def gvc(name, created)
    { "name" => name, "created" => created.is_a?(Time) ? created.iso8601 : created }
  end

  context "with a stale fixture app" do
    let(:gvcs) { [gvc("dummy-test-valid-pre-deletion-hook-bbbb-cccc", six_weeks_ago)] }

    it "deletes it from the suite's org and reports it" do
      sweep

      expect(api).to have_received(:gvc_delete)
        .with(org: org, gvc: "dummy-test-valid-pre-deletion-hook-bbbb-cccc")
      expect(output.string).to include("Deleted stale app 'dummy-test-valid-pre-deletion-hook-bbbb-cccc'")
    end
  end

  context "with a fixture app younger than the minimum age" do
    let(:gvcs) do
      [gvc("dummy-test-full-bbbb", now - StaleDummyAppSweeper::MIN_AGE_SECONDS + 60)]
    end

    it "keeps it, because a concurrent run may still be using it" do
      sweep

      expect(api).not_to have_received(:gvc_delete)
      expect(output.string).to include("Keeping 'dummy-test-full-bbbb': it is only")
    end
  end

  context "with an old fixture app carrying this run's global identifier" do
    let(:gvcs) { [gvc("dummy-test-full-#{current_identifier}", six_weeks_ago)] }

    it "keeps it" do
      sweep

      expect(api).not_to have_received(:gvc_delete)
      expect(output.string).to include("Keeping 'dummy-test-full-aaaa': it belongs to this run")
    end
  end

  context "with old GVCs outside the dummy-test naming boundary" do
    let(:gvcs) do
      [
        gvc("dummy-test-upstream", six_weeks_ago),
        gvc("production-app", six_weeks_ago),
        gvc("not-dummy-test-bbbb", six_weeks_ago),
        gvc("dummy-test-secrets", six_weeks_ago),
        gvc("dummy-test-secrets-policy", six_weeks_ago)
      ]
    end

    it "never considers them" do
      sweep

      expect(api).not_to have_received(:gvc_delete)
      expect(output.string).to include("Found 0 test fixture(s), ignoring 5 other GVC(s)")
    end
  end

  context "with an old fixture app whose creation time is missing or unparseable" do
    let(:gvcs) do
      [
        gvc("dummy-test-full-bbbb", nil),
        gvc("dummy-test-full-cccc", ""),
        gvc("dummy-test-full-dddd", "not-a-timestamp")
      ]
    end

    it "keeps it instead of guessing its age" do
      sweep

      expect(api).not_to have_received(:gvc_delete)
      expect(output.string.scan("its creation time is unknown").length).to eq(3)
    end
  end

  context "when the GVC list cannot be read" do
    before do
      allow(api).to receive(:gvc_list).with(org: org).and_raise("500 from the API")
    end

    it "deletes nothing and does not fail the suite" do
      expect { sweep }.not_to raise_error

      expect(api).not_to have_received(:gvc_delete)
      expect(output.string).to include("Skipped the sweep: could not list GVCs in org 'org-for-tests'")
    end
  end

  context "when deleting a stale app fails" do
    let(:gvcs) do
      [
        gvc("dummy-test-full-bbbb", six_weeks_ago),
        gvc("dummy-test-full-cccc", six_weeks_ago)
      ]
    end

    before do
      allow(api).to receive(:gvc_delete).with(org: org, gvc: "dummy-test-full-bbbb").and_raise("409 from the API")
    end

    it "reports the failure, keeps sweeping, and does not fail the suite" do
      expect { sweep }.not_to raise_error

      expect(api).to have_received(:gvc_delete).with(org: org, gvc: "dummy-test-full-cccc")
      expect(output.string).to include("Failed to delete stale app 'dummy-test-full-bbbb'")
    end
  end

  describe "fixtures that carry a volumeset" do
    let(:stale) { "dummy-test-full-bbbb-cccc" }
    let(:gvcs) { [gvc(stale, six_weeks_ago)] }

    before do
      allow(api).to receive(:list_volumesets).with(org: org, gvc: stale).and_return(
        { "items" => [{ "name" => "postgres",
                        "status" => { "workloadLinks" => ["/org/#{org}/gvc/#{stale}/workload/postgres"] } }] }
      )
    end

    it "clears the volumeset and its workloads before the GVC, as Command::Delete does" do
      sweep

      expect(api).to have_received(:delete_workload).with(org: org, gvc: stale, workload: "postgres").ordered
      expect(api).to have_received(:delete_volumeset).with(org: org, gvc: stale, volumeset: "postgres").ordered
      expect(api).to have_received(:gvc_delete).with(org: org, gvc: stale).ordered
    end

    it "keeps the app for a later run when its volumesets cannot be cleared" do
      allow(api).to receive(:delete_volumeset).and_raise("409 from the API")

      sweep

      expect(api).not_to have_received(:gvc_delete).with(org: org, gvc: stale)
      expect(output.string).to include("could not clear its volumesets")
    end
  end

  # `dummy_test_app` accepts any suffix, so a name it can generate must stay inside the
  # boundary. A generated name the pattern rejected would silently stop being registered
  # for cleanup, which is the leak this whole change exists to close.
  context "with a stale fixture whose suffix has several segments" do
    let(:gvcs) { [gvc("dummy-test-full-bbbb-with-a-trailing-tail", six_weeks_ago)] }

    it "sweeps it, because `dummy_test_app` can generate that name" do
      sweep

      expect(api).to have_received(:gvc_delete).with(org: org, gvc: "dummy-test-full-bbbb-with-a-trailing-tail")
    end
  end
end
