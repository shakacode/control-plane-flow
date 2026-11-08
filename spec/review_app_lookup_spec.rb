# frozen_string_literal: true

require "spec_helper"
require "open3"
require "yaml"

describe "Review app existence lookup" do # rubocop:disable RSpec/DescribeClass
  let(:script) do
    YAML.safe_load_file(Cpflow.root_path.join(".github/workflows/cpflow-deploy-review-app.yml"), aliases: true)
        .fetch("jobs").fetch("deploy").fetch("steps").find { |step| step["id"] == "tracked-deployment" }
                                                     .fetch("with").fetch("script")
  end

  it "recovers from a transient provider failure" do
    expect(lookup([502, 200])).to include("requests" => 2, "tracked" => "true", "error" => nil)
  end

  it "recovers from a dropped transport connection" do
    expect(lookup(["disconnect", 200])).to include("requests" => 2, "tracked" => "true", "error" => nil)
  end

  it "does not retry a missing app or rejected credentials" do
    expect(lookup([404])).to include("requests" => 1, "tracked" => "false")
    expect(lookup([403])).to include("requests" => 1, "error" => include("403"))
  end

  it "bounds repeated provider errors and keeps credentials out of errors" do
    result = lookup([502, 502, 502])

    expect(result).to include("requests" => 3, "error" => include("502"))
    expect(result.fetch("error")).not_to include("fixture-token", "private-response")
  end

  def lookup(statuses)
    stdout, stderr, process = Open3.capture3("node", "-e", node_runner,
                                             stdin_data: JSON.generate(script:, statuses:))
    expect(process).to be_success, stderr
    JSON.parse(stdout)
  end

  def node_runner
    <<~JS
      const http = require('http');
      const {spawn} = require('child_process');
      const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
      let requests = 0;
      const result = {error: null};
      const server = http.createServer((req, res) => {
        if (req.headers.authorization !== 'Bearer fixture-token') throw new Error('Unexpected authorization');
        const status = input.statuses[Math.min(requests++, input.statuses.length - 1)];
        if (status === 'disconnect') {req.socket.destroy(); return;}
        res.writeHead(status); res.end('private-response');
      });
      server.listen(0, '127.0.0.1', async () => {
        const url = `http://127.0.0.1:${server.address().port}/`;
        const expected = 'https://api.cpln.io/org/staging/gvc/app-review-427';
        const exec = {getExecOutput: async (command, args, options) => {
          if (command !== 'curl' || !args.includes(expected) || args.some(arg => arg.includes('fixture-token'))) {
            throw new Error('Unexpected command or exposed credential');
          }
          return new Promise((resolve, reject) => {
            const child = spawn(command, args.map(arg => arg === expected ? url : arg));
            let stdout = '', stderr = '';
            child.stdout.on('data', data => stdout += data);
            child.stderr.on('data', data => stderr += data);
            child.on('error', reject);
            child.on('close', exitCode => resolve({exitCode, stdout, stderr}));
            child.stdin.end(options.input);
          });
        }};
        const fetch = () => {throw new Error('Unexpected direct network access');};
        Object.assign(process.env, {CPLN_TOKEN: 'fixture-token', CPLN_ORG: 'staging', APP_NAME: 'app-review-427'});
        try {
          await new Function('exec', 'core', 'fetch', `return (async () => {${input.script}})()`)(
            exec, {setOutput: (key, value) => result[key] = value}, fetch);
        } catch (error) {result.error = error.message;}
        server.close(() => process.stdout.write(JSON.stringify({...result, requests})));
      });
    JS
  end
end
