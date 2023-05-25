# frozen_string_literal: true

module Scripts
  module_function

  def assert_replicas(gvc:, workload:, location:)
    <<~SHELL
      REPLICAS_QTY=$( \
        curl ${CPLN_ENDPOINT}/org/shakacode-staging/gvc/#{gvc}/workload/#{workload}/deployment/#{location} \
        -H "Authorization: ${CONTROLPLANE_TOKEN}" -s | grep -o '"replicas":[0-9]*' | grep -o '[0-9]*')

      if [ "$REPLICAS_QTY" -gt 0 ]; then
        echo "-- MULTIPLE REPLICAS ATTEMPT: $REPLICAS_QTY --"
        exit -1
      fi
    SHELL
  end

  def helpers_cleanup
    <<~SHELL
      unset CONTROLPLANE_RUNNER
    SHELL
  end

  # NOTE: please escape all '/' as '//' (as it is ruby interpolation here as well)
  def http_dummy_server_ruby
    'require "socket";s=TCPServer.new(ENV["PORT"]);' \
      'loop do c=s.accept;c.puts("HTTP/1.1 200 OK\\nContent-Length: 2\\n\\nOk");c.close end'
  end

  def http_ping_ruby
    'require "net/http";uri=URI(ENV["CPLN_GLOBAL_ENDPOINT"]);loop do puts(Net::HTTP.get(uri));sleep(5);end'
  end
end
