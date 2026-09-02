# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "yaml"

RSpec.describe "GitHub Actions dependency policy" do # rubocop:disable RSpec/DescribeClass
  let(:workflow_files) { Dir[File.expand_path("../.github/workflows/**/*.{yml,yaml}", __dir__)] }
  let(:action_files) do
    [
      *workflow_files,
      *Dir[File.expand_path("../.github/actions/**/action.{yml,yaml}", __dir__)]
    ].sort
  end

  def walk_yaml(value, path = [], &block)
    yield(value, path)

    case value
    when Hash
      value.each { |key, child| walk_yaml(child, [*path, key], &block) }
    when Array
      value.each_with_index { |child, index| walk_yaml(child, [*path, index], &block) }
    end
  end

  def exact_release_tag?(value)
    value.to_s.match?(/\Av\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/)
  end

  it "distinguishes exact release tags from moving version aliases" do
    expect(exact_release_tag?("v1.2.3")).to be(true)
    expect(exact_release_tag?("v1.2.3-rc.1")).to be(true)
    expect(exact_release_tag?("v1")).to be(false)
    expect(exact_release_tag?("v1.2")).to be(false)
  end

  it "pins every external action to a reviewed commit with an auditable version comment" do
    violations = action_files.flat_map do |path|
      File.readlines(path).filter_map.with_index(1) do |line, line_number|
        match = line.match(/^\s*(?:-\s*)?uses:\s*([^@\s#]+)@([^\s#]+)(?:\s+#\s*(\S.*))?\s*$/)
        next unless match

        repository, ref, version_comment = match.captures
        next if repository.start_with?("./") || repository.start_with?("docker://")

        next if ref.match?(/\A[0-9a-f]{40}\z/) && exact_release_tag?(version_comment)

        "#{Pathname(path).relative_path_from(Pathname(__dir__).parent)}:#{line_number}: #{line.strip}"
      end
    end

    expect(violations).to(
      be_empty,
      "external actions must use a lowercase 40-hex commit and exact release-tag comment:\n#{violations.join("\n")}"
    )

    workflow_config = YAML.safe_load_file(File.expand_path("../.agents/agent-workflow.yml", __dir__), aliases: false)
    external_repositories = action_files.flat_map do |path|
      File.readlines(path).filter_map do |line|
        match = line.match(/^\s*(?:-\s*)?uses:\s*([^@\s#]+)@/)
        match[1] if match && !match[1].start_with?("./", "docker://")
      end
    end.uniq.sort

    expect(workflow_config.fetch("trusted_actions").sort).to eq(external_repositories)
  end

  it "lets Dependabot propose reviewed GitHub Actions updates" do
    config = YAML.safe_load_file(File.expand_path("../.github/dependabot.yml", __dir__), aliases: false)
    expected_directories = ["/"]
    action_files.reject { |path| workflow_files.include?(path) }.each do |path|
      next unless File.read(path).match?(%r{^\s*(?:-\s*)?uses:\s*(?!\./|docker://)[^@\s#]+@})

      relative_directory = Pathname(path).dirname.relative_path_from(Pathname(__dir__).parent)
      expected_directories << "/#{relative_directory}"
    end
    actions_updates = config.fetch("updates").select { |update| update["package-ecosystem"] == "github-actions" }

    expect(actions_updates.map { |update| update["directory"] }.sort).to eq(expected_directories.uniq.sort)
    expect(actions_updates).to all(include("schedule" => { "interval" => "weekly" }))
  end

  it "keeps expressions out of shell scripts and passes only named reusable-workflow secrets" do
    violations = action_files.flat_map do |path|
      document = YAML.safe_load_file(path, aliases: true)

      [].tap do |file_violations|
        walk_yaml(document) do |value, yaml_path|
          if yaml_path.last == "run" && value.is_a?(String) && value.include?("${{")
            file_violations << "#{File.basename(path)}: #{yaml_path.join('.')} interpolates an expression in run"
          elsif yaml_path.last == "secrets" && value == "inherit"
            file_violations << "#{File.basename(path)}: #{yaml_path.join('.')} inherits every secret"
          end
        end
      end
    end

    expect(violations).to be_empty, violations.join("\n")
  end

  it "uses least-privilege workflow defaults and never persists checkout credentials" do
    violations = workflow_files.flat_map do |path|
      workflow = YAML.safe_load_file(path, aliases: true)
      file_violations = []
      unless workflow["permissions"].is_a?(Hash)
        file_violations << "#{File.basename(path)}: missing top-level permissions"
      end

      walk_yaml(workflow) do |value, yaml_path|
        next unless value.is_a?(Hash) && value["uses"]&.start_with?("actions/checkout@")
        next if value.dig("with", "persist-credentials") == false

        file_violations << "#{File.basename(path)}: #{yaml_path.join('.')} persists checkout credentials"
      end

      file_violations
    end

    expect(violations).to be_empty, violations.join("\n")
  end
end
