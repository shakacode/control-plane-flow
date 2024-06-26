# frozen_string_literal: true

class ControlplaneApi # rubocop:disable Metrics/ClassLength
  def list_orgs
    api_json("/org", method: :get)
  end

  def gvc_list(org:)
    api_json("/org/#{org}/gvc", method: :get)
  end

  def gvc_get(org:, gvc:)
    api_json("/org/#{org}/gvc/#{gvc}", method: :get)
  end

  def gvc_delete(org:, gvc:)
    api_json("/org/#{org}/gvc/#{gvc}", method: :delete)
  end

  def query_images(org:, gvc:, gvc_op_type:)
    terms = [
      {
        property: "repository",
        op: gvc_op_type,
        value: gvc
      }
    ]

    query("/org/#{org}/image", terms)
  end

  def fetch_image_details(org:, image:)
    api_json("/org/#{org}/image/#{image}", method: :get)
  end

  def image_delete(org:, image:)
    api_json("/org/#{org}/image/#{image}", method: :delete)
  end

  def log_get(org:, gvc:, workload: nil, replica: nil, from: nil, to: nil) # rubocop:disable Metrics/ParameterLists
    query = { gvc: gvc }
    query[:workload] = workload if workload
    query[:replica] = replica if replica
    query = query.map { |k, v| %(#{k}="#{v}") }.join(",").then { "{#{_1}}" }

    params = { query: query }
    params[:from] = "#{from}000000000" if from
    params[:to] = "#{to}000000000" if to
    params[:limit] = "5000"
    # params << "delay_for=0"
    # params << "limit=30"
    # params << "direction=forward"
    params = params.map { |k, v| %(#{k}=#{CGI.escape(v)}) }.join("&")

    api_json("/logs/org/#{org}/loki/api/v1/query_range?#{params}", method: :get, host: :logs)
  end

  def query_workloads(org:, gvc:, workload:, gvc_op_type:, workload_op_type:) # rubocop:disable Metrics/MethodLength
    terms = [
      {
        rel: "gvc",
        op: gvc_op_type,
        value: gvc
      },
      {
        property: "name",
        op: workload_op_type,
        value: workload
      }
    ]

    query("/org/#{org}/workload", terms)
  end

  def workload_list(org:, gvc:)
    api_json("/org/#{org}/gvc/#{gvc}/workload", method: :get)
  end

  def workload_list_by_org(org:)
    api_json("/org/#{org}/workload", method: :get)
  end

  def workload_get(org:, gvc:, workload:)
    api_json("/org/#{org}/gvc/#{gvc}/workload/#{workload}", method: :get)
  end

  def update_workload(org:, gvc:, workload:, data:)
    api_json("/org/#{org}/gvc/#{gvc}/workload/#{workload}", method: :patch, body: data)
  end

  def workload_deployments(org:, gvc:, workload:)
    api_json("/org/#{org}/gvc/#{gvc}/workload/#{workload}/deployment", method: :get)
  end

  def delete_workload(org:, gvc:, workload:)
    api_json("/org/#{org}/gvc/#{gvc}/workload/#{workload}", method: :delete)
  end

  def list_volumesets(org:, gvc:)
    api_json("/org/#{org}/gvc/#{gvc}/volumeset", method: :get)
  end

  def delete_volumeset(org:, gvc:, volumeset:)
    api_json("/org/#{org}/gvc/#{gvc}/volumeset/#{volumeset}", method: :delete)
  end

  def fetch_domain(org:, domain:)
    api_json("/org/#{org}/domain/#{domain}", method: :get)
  end

  def list_domains(org:)
    api_json("/org/#{org}/domain", method: :get)
  end

  def update_domain(org:, domain:, data:)
    api_json("/org/#{org}/domain/#{domain}", method: :patch, body: data)
  end

  def fetch_secret(org:, secret:)
    api_json("/org/#{org}/secret/#{secret}", method: :get)
  end

  def delete_secret(org:, secret:)
    api_json("/org/#{org}/secret/#{secret}", method: :delete)
  end

  def fetch_identity(org:, gvc:, identity:)
    api_json("/org/#{org}/gvc/#{gvc}/identity/#{identity}", method: :get)
  end

  def fetch_policy(org:, policy:)
    api_json("/org/#{org}/policy/#{policy}", method: :get)
  end

  def delete_policy(org:, policy:)
    api_json("/org/#{org}/policy/#{policy}", method: :delete)
  end

  private

  def fetch_query_pages(result)
    loop do
      next_page_url = result["links"].find { |link| link["rel"] == "next" }&.dig("href")
      break unless next_page_url

      next_page_result = api_json(next_page_url, method: :get)
      result["items"] += next_page_result["items"]
      result["links"] = next_page_result["links"]
    end
  end

  def query(url, terms)
    body = {
      kind: "string",
      spec: {
        match: "all",
        terms: terms
      }
    }

    result = api_json("#{url}/-query", method: :post, body: body)
    fetch_query_pages(result)

    result
  end

  def api_json(...)
    ControlplaneApiDirect.new.call(...)
  end
end
