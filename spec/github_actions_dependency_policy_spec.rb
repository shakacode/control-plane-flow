# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "tmpdir"
require "yaml"

RSpec.describe "GitHub Actions dependency policy" do # rubocop:disable RSpec/DescribeClass
  let(:workflow_files) { Dir[File.expand_path("../.github/workflows/**/*.{yml,yaml}", __dir__)] }
  let(:action_files) do
    [
      *workflow_files,
      *Dir[File.expand_path("../.github/actions/**/action.{yml,yaml}", __dir__)]
    ].sort
  end

  def walk_yaml(value, path = [], visited_containers: {}.compare_by_identity, &block)
    return if yaml_container_seen?(value, visited_containers)

    yield(value, path)
    yaml_children(value).each do |path_segment, child|
      walk_yaml(child, [*path, path_segment], visited_containers: visited_containers, &block)
    end
  end

  def yaml_container_seen?(value, visited_containers)
    return false unless value.is_a?(Hash) || value.is_a?(Array)

    visited_containers.key?(value).tap { visited_containers[value] = true }
  end

  def yaml_children(value)
    return value.to_a if value.is_a?(Hash)
    return value.each_with_index.map { |child, index| [index, child] } if value.is_a?(Array)

    []
  end

  def exact_release_tag?(value)
    value.to_s.match?(/\Av\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/)
  end

  def external_action_references(path)
    collect_external_action_references(Psych.parse_file(path))
  end

  def collect_external_action_references(node, yaml_path = [], references = [])
    collect_external_action_reference_node(node, yaml_path, references)
    references
  end

  def collect_external_action_reference_node(node, yaml_path, references)
    case node
    when Psych::Nodes::Alias
      append_aliased_action_mapping(node, yaml_path, references)
    when Psych::Nodes::Mapping
      collect_external_action_references_from_mapping(node, yaml_path, references)
    when Psych::Nodes::Sequence
      collect_external_action_references_from_sequence(node, yaml_path, references)
    when Psych::Nodes::Document, Psych::Nodes::Stream
      collect_external_action_references_from_document(node, yaml_path, references)
    end
  end

  def append_aliased_action_mapping(node, yaml_path, references)
    return unless action_structure_path?(yaml_path)

    references << indirect_action_reference("aliased action mapping", node.start_line + 1)
  end

  def collect_external_action_references_from_sequence(node, yaml_path, references)
    node.children.each_with_index do |child, index|
      collect_external_action_references(child, [*yaml_path, index], references)
    end
  end

  def collect_external_action_references_from_document(node, yaml_path, references)
    node.children.each { |child| collect_external_action_references(child, yaml_path, references) }
  end

  def collect_external_action_references_from_mapping(node, yaml_path, references)
    node.children.each_slice(2) do |key, value|
      append_external_action_reference(key, value, yaml_path, references)
      path_segment = key.is_a?(Psych::Nodes::Scalar) ? key.value : "<indirect-key>"
      collect_external_action_references(value, [*yaml_path, path_segment], references)
    end
  end

  def append_external_action_reference(key, value, yaml_path, references)
    unless key.is_a?(Psych::Nodes::Scalar)
      append_indirect_action_mapping_key(key, yaml_path, references)
      return
    end

    return append_merged_action_mapping(key, yaml_path, references) if key.value == "<<"
    return unless key.value == "uses" && action_mapping_path?(yaml_path)

    reference = external_action_reference(value, key.start_line + 1)
    references << reference if reference
  end

  def append_merged_action_mapping(key, yaml_path, references)
    return unless action_structure_path?(yaml_path)

    references << indirect_action_reference("merged action mapping", key.start_line + 1)
  end

  def append_indirect_action_mapping_key(key, yaml_path, references)
    return unless action_structure_path?(yaml_path)

    references << indirect_action_reference("indirect action mapping key", key.start_line + 1)
  end

  def action_mapping_path?(yaml_path)
    workflow_job_path?(yaml_path) || workflow_step_path?(yaml_path) || composite_step_path?(yaml_path)
  end

  def workflow_job_path?(yaml_path)
    yaml_path.length == 2 && yaml_path.first == "jobs"
  end

  def workflow_step_path?(yaml_path)
    yaml_path.length == 4 && yaml_path.values_at(0, 2) == %w[jobs steps] && yaml_path.last.is_a?(Integer)
  end

  def composite_step_path?(yaml_path)
    yaml_path.length == 3 && yaml_path.first(2) == %w[runs steps] && yaml_path.last.is_a?(Integer)
  end

  def action_structure_path?(yaml_path)
    return true if yaml_path.empty? || [%w[jobs], %w[runs]].include?(yaml_path)
    return true if action_mapping_path?(yaml_path)
    return true if yaml_path.length == 3 && yaml_path.values_at(0, 2) == %w[jobs steps]

    yaml_path == %w[runs steps]
  end

  def indirect_action_reference(value, line_number)
    { value: value, repository: nil, ref: nil, kind: :repository, line_number: line_number }
  end

  def external_action_reference(value_node, line_number)
    return indirect_action_reference("non-scalar uses value", line_number) unless value_node.is_a?(Psych::Nodes::Scalar)

    value = value_node.value
    return if value.start_with?("./")

    kind = value.start_with?("docker://") ? :docker : :repository
    build_external_action_reference(value, kind, line_number)
  end

  def build_external_action_reference(value, kind, line_number)
    match = external_action_reference_match(value, kind)
    trusted_repository = kind == :repository ? match&.[](:trusted_repository)&.downcase : nil
    {
      value: value, repository: match&.[](:repository), ref: match&.[](:ref), kind: kind,
      trusted_repository: trusted_repository, line_number: line_number
    }
  end

  def external_action_reference_match(value, kind)
    return value.match(%r{\A(?<repository>docker://[^@\s#]+)@(?<ref>[^\s#]+)\z}) if kind == :docker

    value.match(%r{\A(?<repository>(?<trusted_repository>[^/@\s#]+/[^/@\s#]+)(?:/[^/@\s#]+)*)@(?<ref>[^\s#]+)\z})
  end

  def external_action_policy_violations(path)
    relative_path = Pathname(path).relative_path_from(Pathname(__dir__).parent)
    source_lines = File.readlines(path)

    external_action_references(path).filter_map do |reference|
      external_action_policy_violation(reference, source_lines, relative_path)
    end
  end

  def action_uses_line_pattern
    /
      \A\s*(?:-\s*)?(?:uses|"uses"|'uses')\s*:\s*
      (?<quote>["']?)(?<repository>[^@\s#"']+)@(?<ref>[^\s#"']+)\k<quote>
      (?:\s+\#\s*(?<version_comment>\S.*))?\s*\z
    /x
  end

  def external_action_policy_violation(reference, source_lines, relative_path)
    source_line = source_lines.fetch(reference[:line_number] - 1)
    source_match = source_line.match(action_uses_line_pattern)
    unless matching_action_source?(reference, source_match)
      return "#{relative_path}:#{reference[:line_number]}: #{reference[:value]} must be " \
             "#{canonical_action_source_requirement(reference)}"
    end

    return if immutable_action_reference?(reference, source_match)

    "#{relative_path}:#{reference[:line_number]}: #{source_line.strip}"
  end

  def matching_action_source?(reference, source_match)
    return false unless reference[:repository] && reference[:ref] && source_match

    "#{source_match[:repository]}@#{source_match[:ref]}" == reference[:value]
  end

  def canonical_action_source_requirement(reference)
    return "a standalone uses: docker://image@sha256:digest entry" if reference[:kind] == :docker

    "a standalone uses: repository@ref entry with an auditable same-line release-tag comment"
  end

  def immutable_action_reference?(reference, source_match)
    return reference[:ref].match?(/\Asha256:[0-9a-fA-F]{64}\z/) if reference[:kind] == :docker

    reference[:ref].match?(/\A[0-9a-f]{40}\z/) && exact_release_tag?(source_match[:version_comment])
  end

  def dependabot_action_directory(path, workflow_files)
    return "/" if workflow_files.include?(path)
    return unless external_action_references(path).any? { |reference| reference[:kind] == :repository }

    relative_directory = Pathname(path).dirname.relative_path_from(Pathname(__dir__).parent)
    "/#{relative_directory}"
  end

  it "distinguishes exact release tags from moving version aliases" do
    expect(exact_release_tag?("v1.2.3")).to be(true)
    expect(exact_release_tag?("v1.2.3-rc.1")).to be(true)
    expect(exact_release_tag?("v1")).to be(false)
    expect(exact_release_tag?("v1.2")).to be(false)
  end

  it "rejects unpinned external actions behind quoted YAML uses keys" do
    Dir.mktmpdir("github-actions-policy") do |directory|
      path = Pathname(directory).join("quoted-uses.yml")
      path.write(<<~YAML)
        jobs:
          build:
            steps:
              - "uses": evil/action@v1
      YAML

      expect(external_action_policy_violations(path)).to include(match(%r{evil/action@v1}))
    end
  end

  it "accepts exact pins when the YAML uses key and value are quoted" do
    Dir.mktmpdir("github-actions-policy") do |directory|
      path = Pathname(directory).join("quoted-uses.yml")
      path.write(<<~YAML)
        jobs:
          build:
            steps:
              - "uses": "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd" # v6.0.2
      YAML

      expect(external_action_policy_violations(path)).to be_empty
    end
  end

  it "requires Docker actions to use an immutable image digest" do
    Dir.mktmpdir("github-actions-policy") do |directory|
      mutable_path = Pathname(directory).join("mutable-docker.yml")
      pinned_path = Pathname(directory).join("pinned-docker.yml")
      mutable_path.write("runs:\n  steps:\n    - uses: docker://alpine:latest\n")
      pinned_path.write("runs:\n  steps:\n    - uses: docker://alpine@sha256:#{'a' * 64}\n")

      expect(external_action_policy_violations(mutable_path)).to include(match(%r{docker://alpine:latest}))
      expect(external_action_policy_violations(pinned_path)).to be_empty
    end
  end

  it "does not claim Dependabot coverage for unsupported Docker container actions" do
    Dir.mktmpdir("github-actions-policy", Pathname(__dir__).parent) do |directory|
      path = Pathname(directory).join("action.yml")
      path.write("runs:\n  steps:\n    - uses: docker://alpine@sha256:#{'a' * 64}\n")

      expect(dependabot_action_directory(path, [])).to be_nil
    end
  end

  it "normalizes action subpaths to the owner/repository trust identity" do
    Dir.mktmpdir("github-actions-policy") do |directory|
      path = Pathname(directory).join("action-subpath.yml")
      path.write(<<~YAML)
        runs:
          steps:
            - uses: Owner/Repository/subpath@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
      YAML

      reference = external_action_references(path).fetch(0)
      expect(reference[:trusted_repository]).to eq("owner/repository")
      expect(external_action_policy_violations(path)).to be_empty
    end
  end

  it "ignores unrelated uses and alias keys outside action-bearing mappings" do
    Dir.mktmpdir("github-actions-policy") do |directory|
      path = Pathname(directory).join("unrelated-uses.yml")
      path.write(<<~YAML)
        metadata:
          environment_key: &environment_key CUSTOM_FLAG
        jobs:
          build:
            steps:
              - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
                with:
                  uses: harmless-input
                env:
                  *environment_key: enabled
      YAML

      expect(external_action_references(path).length).to eq(1)
      expect(external_action_policy_violations(path)).to be_empty
    end
  end

  it "rejects external uses forms whose release comment cannot bind to one standalone entry" do
    pinned_action = "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd"
    unsafe_documents = {
      "aliased-value" => <<~YAML,
        metadata:
          action: &action #{pinned_action}
        jobs:
          build:
            steps:
              - uses: *action # v6.0.2
      YAML
      "aliased-key" => <<~YAML,
        metadata:
          key: &uses uses
        jobs:
          build:
            steps:
              - *uses: evil/action@v1
      YAML
      "merge-comment" => <<~YAML,
        defaults: &defaults
          uses: #{pinned_action}
        jobs:
          build:
            steps:
              - <<: *defaults # v6.0.2
      YAML
      "duplicate-value" => <<~YAML,
        jobs:
          build:
            steps:
              - uses: #{pinned_action} # v6.0.2
              - uses: #{pinned_action}
      YAML
      "multiline-value" => <<~YAML,
        jobs:
          build:
            steps:
              - uses: >-
                  #{pinned_action}
      YAML
      "flow-style" => <<~YAML
        jobs:
          build:
            steps:
              - { uses: #{pinned_action} } # v6.0.2
      YAML
    }

    Dir.mktmpdir("github-actions-policy") do |directory|
      unsafe_documents.each do |name, document|
        path = Pathname(directory).join("#{name}.yml")
        path.write(document)

        expect(external_action_policy_violations(path)).not_to be_empty, name
      end
    end
  end

  it "binds the release-tag comment to the parsed uses entry's source line" do
    Dir.mktmpdir("github-actions-policy") do |directory|
      path = Pathname(directory).join("block-scalar-spoof.yml")
      path.write(<<~YAML)
        jobs:
          build:
            steps:
              - run: |
                  uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
              - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
      YAML

      expect(external_action_policy_violations(path)).to include(match(%r{actions/checkout@de0fac2e4500}))
    end
  end

  it "terminates when the parsed YAML contains a recursive alias" do
    Dir.mktmpdir("github-actions-policy") do |directory|
      path = Pathname(directory).join("recursive-alias.yml")
      path.write(<<~YAML)
        metadata:
          loop: &loop
            - *loop
      YAML

      walked_paths = []
      walk_yaml(YAML.safe_load_file(path, aliases: true)) { |_value, yaml_path| walked_paths << yaml_path }

      expect(walked_paths).to include(%w[metadata loop])
      expect(external_action_policy_violations(path)).to be_empty
    end
  end

  it "pins every external action to a reviewed commit with an auditable version comment" do
    violations = action_files.flat_map { |path| external_action_policy_violations(path) }

    expect(violations).to(
      be_empty,
      "repository actions must use a lowercase 40-hex commit and exact release-tag comment; " \
      "Docker actions must use a sha256 digest:\n#{violations.join("\n")}"
    )

    workflow_config = YAML.safe_load_file(File.expand_path("../.agents/agent-workflow.yml", __dir__), aliases: false)
    external_repositories = action_files.flat_map do |path|
      external_action_references(path).filter_map do |reference|
        reference[:trusted_repository] if reference[:kind] == :repository
      end
    end.uniq.sort

    expect(workflow_config.fetch("trusted_actions").sort).to eq(external_repositories)
  end

  it "pins the RSpec Control Plane CLI and scopes its token to the consuming steps" do
    path = File.expand_path("../.github/workflows/rspec-shared.yml", __dir__)
    workflow = YAML.safe_load_file(path, aliases: true)
    job = workflow.fetch("jobs").fetch("rspec")
    steps = job.fetch("steps")
    install_step = steps.find { |step| step["name"] == "Install Control Plane tools" }

    expect(job.fetch("env", {})).not_to have_key("CPLN_TOKEN_CI")
    expect(install_step.fetch("run")).to include("sudo npm install -g @controlplane/cli@3.11.0")

    token_step_names = steps.filter_map do |step|
      step["name"] if step.fetch("env", {}).key?("CPLN_TOKEN_CI")
    end
    expect(token_step_names).to contain_exactly("Setup Control Plane tools", "Run tests")
    expect(steps.filter { |step| token_step_names.include?(step["name"]) }).to(
      all(include("env" => include("CPLN_TOKEN_CI" => "${{ secrets.CPLN_TOKEN }}")))
    )
  end

  it "lets Dependabot propose reviewed GitHub Actions updates" do
    config = YAML.safe_load_file(File.expand_path("../.github/dependabot.yml", __dir__), aliases: false)
    expected_directories = action_files.filter_map { |path| dependabot_action_directory(path, workflow_files) }
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
