# frozen_string_literal: true

class ControlplaneApi
  def gvc_list(org:)
    api_json("/org/#{org}/gvc", method: :get)
  end

  def gvc_get(org:, gvc:)
    api_json("/org/#{org}/gvc/#{gvc}", method: :get)
  end

  def gvc_delete(org:, gvc:)
    api_json("/org/#{org}/gvc/#{gvc}", method: :delete)
  end

  def image_delete(org:, image:)
    api_json("/org/#{org}/image/#{image}", method: :delete)
  end

  def log_get(org:, gvc:, workload: nil, from: nil, to: nil)
    query = { gvc: gvc }
    query[:workload] = workload if workload
    query = query.map { |k, v| %(#{k}="#{v}") }.join(",").then { "{#{_1}}" }

    params = { query: query }
    params[:from] = "#{from}000000000" if from
    params[:to] = "#{to}000000000" if to
    # params << "delay_for=0"
    # params << "limit=30"
    # params << "direction=forward"
    params = params.map { |k, v| %(#{k}=#{CGI.escape(v)}) }.join("&")

    api_json_direct("/logs/org/#{org}/loki/api/v1/query_range?#{params}", method: :get, host: :logs)
  end

  def query_workloads(org:, gvc:, workload:, gvc_op_type:, workload_op_type:) # rubocop:disable Metrics/MethodLength
    body = {
      kind: "string",
      spec: {
        match: "all",
        terms: [
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
      }
    }

    api_json("/org/#{org}/workload/-query", method: :post, body: body)
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

  def list_domains(org:)
    api_json("/org/#{org}/domain", method: :get)
  end

  def update_domain(org:, domain:, data:)
    api_json("/org/#{org}/domain/#{domain}", method: :patch, body: data)
  end

  private

  # switch between cpln rest and api
  def api_json(...)
    ControlplaneApiDirect.new.call(...)
  end

  # only for api (where not impelemented in cpln rest)
  def api_json_direct(...)
    ControlplaneApiDirect.new.call(...)
  end
end
