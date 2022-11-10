# frozen_string_literal: true

class ControlplaneApi
  def gvc_get(org:, gvc:)
    api_json("/org/#{org}/gvc/#{gvc}", method: :get)
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

  def workload_get(org:, gvc:, workload:)
    api_json("/org/#{org}/gvc/#{gvc}/workload/#{workload}", method: :get)
  end

  def workload_deployments(org:, gvc:, workload:)
    api_json("/org/#{org}/gvc/#{gvc}/workload/#{workload}/deployment", method: :get)
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
