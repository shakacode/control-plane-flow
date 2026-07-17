# frozen_string_literal: true

require "spec_helper"

describe ControlplaneApi do
  let(:api) { described_class.new }
  let(:api_direct) { instance_double(ControlplaneApiDirect) }

  before do
    allow(ControlplaneApiDirect).to receive(:new).and_return(api_direct)
  end

  def stub_api_call(*expected_args, **expected_kwargs)
    response = { "response" => "data" }
    allow(api_direct).to receive(:call).with(*expected_args, **expected_kwargs).and_return(response)
    response
  end

  describe "#list_orgs" do
    it "fetches the orgs list" do
      response = stub_api_call("/org", method: :get)

      expect(api.list_orgs).to eq(response)
    end
  end

  describe "#gvc_list" do
    it "fetches the gvc list for the org" do
      response = stub_api_call("/org/my-org/gvc", method: :get)

      expect(api.gvc_list(org: "my-org")).to eq(response)
    end
  end

  describe "#gvc_get" do
    it "fetches a single gvc" do
      response = stub_api_call("/org/my-org/gvc/my-app", method: :get)

      expect(api.gvc_get(org: "my-org", gvc: "my-app")).to eq(response)
    end
  end

  describe "#gvc_delete" do
    it "deletes the gvc" do
      response = stub_api_call("/org/my-org/gvc/my-app", method: :delete)

      expect(api.gvc_delete(org: "my-org", gvc: "my-app")).to eq(response)
    end
  end

  describe "#query_images" do
    let(:expected_body) do
      {
        kind: "string",
        spec: {
          match: "all",
          terms: [
            {
              property: "repository",
              op: "=",
              value: "my-app"
            }
          ]
        }
      }
    end

    it "queries images by repository" do
      result = { "items" => [{ "name" => "image1" }], "links" => [] }
      allow(api_direct).to receive(:call)
        .with("/org/my-org/image/-query", method: :post, body: expected_body)
        .and_return(result)

      expect(api.query_images(org: "my-org", gvc: "my-app", gvc_op_type: "=")).to eq(result)
    end

    it "fetches all pages of a paginated query" do
      first_page = {
        "items" => [{ "name" => "image1" }],
        "links" => [{ "rel" => "next", "href" => "/org/my-org/image/-query?page=2" }]
      }
      second_page = {
        "items" => [{ "name" => "image2" }],
        "links" => [{ "rel" => "self", "href" => "/org/my-org/image/-query?page=2" }]
      }
      allow(api_direct).to receive(:call)
        .with("/org/my-org/image/-query", method: :post, body: expected_body)
        .and_return(first_page)
      allow(api_direct).to receive(:call)
        .with("/org/my-org/image/-query?page=2", method: :get)
        .and_return(second_page)

      result = api.query_images(org: "my-org", gvc: "my-app", gvc_op_type: "=")

      expect(result["items"]).to eq([{ "name" => "image1" }, { "name" => "image2" }])
      expect(result["links"]).to eq(second_page["links"])
    end
  end

  describe "#fetch_image_details" do
    it "fetches a single image" do
      response = stub_api_call("/org/my-org/image/my-app:123", method: :get)

      expect(api.fetch_image_details(org: "my-org", image: "my-app:123")).to eq(response)
    end
  end

  describe "#image_delete" do
    it "deletes the image" do
      response = stub_api_call("/org/my-org/image/my-app:123", method: :delete)

      expect(api.image_delete(org: "my-org", image: "my-app:123")).to eq(response)
    end
  end

  describe "#log_get" do
    it "queries logs for a gvc with the default limit" do
      response = stub_api_call(
        "/logs/org/my-org/loki/api/v1/query_range?query=%7Bgvc%3D%22my-gvc%22%7D&limit=5000",
        method: :get, host: :logs
      )

      expect(api.log_get(org: "my-org", gvc: "my-gvc")).to eq(response)
    end

    it "includes workload, replica, and nanosecond time bounds when given" do
      escaped_query = "%7Bgvc%3D%22my-gvc%22%2Cworkload%3D%22my-workload%22%2Creplica%3D%22my-replica%22%7D"
      response = stub_api_call(
        "/logs/org/my-org/loki/api/v1/query_range?query=#{escaped_query}" \
        "&from=1700000000000000000&to=1700000060000000000&limit=5000",
        method: :get, host: :logs
      )

      result = api.log_get(
        org: "my-org",
        gvc: "my-gvc",
        workload: "my-workload",
        replica: "my-replica",
        from: 1_700_000_000,
        to: 1_700_000_060
      )

      expect(result).to eq(response)
    end
  end

  describe "#query_workloads" do
    it "queries workloads by gvc and name" do
      expected_body = {
        kind: "string",
        spec: {
          match: "all",
          terms: [
            {
              rel: "gvc",
              op: "=",
              value: "my-app"
            },
            {
              property: "name",
              op: ">",
              value: "my-workload"
            }
          ]
        }
      }
      result = { "items" => [], "links" => [] }
      allow(api_direct).to receive(:call)
        .with("/org/my-org/workload/-query", method: :post, body: expected_body)
        .and_return(result)

      query_result = api.query_workloads(
        org: "my-org",
        gvc: "my-app",
        workload: "my-workload",
        gvc_op_type: "=",
        workload_op_type: ">"
      )

      expect(query_result).to eq(result)
    end
  end

  describe "#workload_list" do
    it "fetches the workloads for a gvc" do
      response = stub_api_call("/org/my-org/gvc/my-app/workload", method: :get)

      expect(api.workload_list(org: "my-org", gvc: "my-app")).to eq(response)
    end
  end

  describe "#workload_list_by_org" do
    it "fetches the workloads for the whole org" do
      response = stub_api_call("/org/my-org/workload", method: :get)

      expect(api.workload_list_by_org(org: "my-org")).to eq(response)
    end
  end

  describe "#workload_get" do
    it "fetches a single workload" do
      response = stub_api_call("/org/my-org/gvc/my-app/workload/my-workload", method: :get)

      expect(api.workload_get(org: "my-org", gvc: "my-app", workload: "my-workload")).to eq(response)
    end
  end

  describe "#update_workload" do
    it "patches the workload with the given data" do
      data = { "spec" => { "suspend" => true } }
      response = stub_api_call("/org/my-org/gvc/my-app/workload/my-workload", method: :patch, body: data)

      expect(api.update_workload(org: "my-org", gvc: "my-app", workload: "my-workload", data: data)).to eq(response)
    end
  end

  describe "#workload_deployments" do
    it "fetches the deployments for a workload" do
      response = stub_api_call("/org/my-org/gvc/my-app/workload/my-workload/deployment", method: :get)

      expect(api.workload_deployments(org: "my-org", gvc: "my-app", workload: "my-workload")).to eq(response)
    end
  end

  describe "#delete_workload" do
    it "deletes the workload" do
      response = stub_api_call("/org/my-org/gvc/my-app/workload/my-workload", method: :delete)

      expect(api.delete_workload(org: "my-org", gvc: "my-app", workload: "my-workload")).to eq(response)
    end
  end

  describe "#list_volumesets" do
    it "fetches the volumesets for a gvc" do
      response = stub_api_call("/org/my-org/gvc/my-app/volumeset", method: :get)

      expect(api.list_volumesets(org: "my-org", gvc: "my-app")).to eq(response)
    end
  end

  describe "#delete_volumeset" do
    it "deletes the volumeset" do
      response = stub_api_call("/org/my-org/gvc/my-app/volumeset/my-volume", method: :delete)

      expect(api.delete_volumeset(org: "my-org", gvc: "my-app", volumeset: "my-volume")).to eq(response)
    end
  end

  describe "#fetch_domain" do
    it "fetches a single domain" do
      response = stub_api_call("/org/my-org/domain/app.example.com", method: :get)

      expect(api.fetch_domain(org: "my-org", domain: "app.example.com")).to eq(response)
    end
  end

  describe "#list_domains" do
    it "fetches the domains for the org" do
      response = stub_api_call("/org/my-org/domain", method: :get)

      expect(api.list_domains(org: "my-org")).to eq(response)
    end
  end

  describe "#update_domain" do
    it "patches the domain with the given data" do
      data = { "spec" => { "ports" => [] } }
      response = stub_api_call("/org/my-org/domain/app.example.com", method: :patch, body: data)

      expect(api.update_domain(org: "my-org", domain: "app.example.com", data: data)).to eq(response)
    end
  end

  describe "#fetch_secret" do
    it "fetches a single secret" do
      response = stub_api_call("/org/my-org/secret/my-secret", method: :get)

      expect(api.fetch_secret(org: "my-org", secret: "my-secret")).to eq(response)
    end
  end

  describe "#delete_secret" do
    it "deletes the secret" do
      response = stub_api_call("/org/my-org/secret/my-secret", method: :delete)

      expect(api.delete_secret(org: "my-org", secret: "my-secret")).to eq(response)
    end
  end

  describe "#fetch_identity" do
    it "fetches a single identity" do
      response = stub_api_call("/org/my-org/gvc/my-app/identity/my-identity", method: :get)

      expect(api.fetch_identity(org: "my-org", gvc: "my-app", identity: "my-identity")).to eq(response)
    end
  end

  describe "#fetch_policy" do
    it "fetches a single policy" do
      response = stub_api_call("/org/my-org/policy/my-policy", method: :get)

      expect(api.fetch_policy(org: "my-org", policy: "my-policy")).to eq(response)
    end
  end

  describe "#delete_policy" do
    it "deletes the policy" do
      response = stub_api_call("/org/my-org/policy/my-policy", method: :delete)

      expect(api.delete_policy(org: "my-org", policy: "my-policy")).to eq(response)
    end
  end
end
