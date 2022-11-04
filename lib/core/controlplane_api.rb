# frozen_string_literal: true

class ControlplaneApi
  def workload_get(org:, gvc:, workload:)
    api_json("/org/#{org}/gvc/#{gvc}/workload/#{workload}", method: :get)
  end

  def workload_deployments(org:, gvc:, workload:)
    api_json("/org/#{org}/gvc/#{gvc}/workload/#{workload}/deployment", method: :get)
  end

  private

  def api_json(url, method:)
    ControlplaneApiDirect.new.call(url, method: method)
  end
end
