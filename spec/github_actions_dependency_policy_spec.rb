# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "tmpdir"
require "yaml"

RSpec.describe "GitHub Actions dependency policy" do # rubocop:disable RSpec/DescribeClass
  let(:workflow_files) { Dir[File.expand_path("../.github/workflows/**/*.{yml,yaml}", __dir__)] }
  let(:approved_top_level_permissions) do
    {
      "check_cpln_links.yml" => { "contents" => "read" },
      "claude-code-review.yml" => {},
      "claude.yml" => {},
      "command_docs.yml" => { "contents" => "read" },
      "cpflow-cleanup-stale-review-apps.yml" => { "contents" => "read" },
      "cpflow-delete-review-app.yml" => {
        "actions" => "write", "contents" => "read", "deployments" => "write",
        "issues" => "write", "pull-requests" => "write"
      },
      "cpflow-deploy-review-app.yml" => {
        "actions" => "write", "contents" => "read", "deployments" => "write",
        "issues" => "write", "pull-requests" => "write"
      },
      "cpflow-deploy-staging.yml" => { "contents" => "read" },
      "cpflow-help-command.yml" => {
        "contents" => "read", "issues" => "write", "pull-requests" => "write"
      },
      "cpflow-promote-staging-to-production.yml" => { "contents" => "read" },
      "cpflow-review-app-help.yml" => { "issues" => "write", "pull-requests" => "write" },
      "rspec-shared.yml" => { "contents" => "read" },
      "rspec-specific.yml" => { "contents" => "read" },
      "rspec.yml" => { "contents" => "read" },
      "rubocop.yml" => { "contents" => "read" },
      "trigger-docs-site.yml" => {}
    }
  end
  let(:action_files) do
    [
      *workflow_files,
      *Dir[File.expand_path("../.github/actions/**/action.{yml,yaml}", __dir__)]
    ].sort
  end

  def walk_yaml(value, path = [], active_containers: {}.compare_by_identity, &block)
    container = value.is_a?(Hash) || value.is_a?(Array)
    return if container && active_containers.key?(value)

    active_containers[value] = true if container
    yield(value, path)
    yaml_children(value).each do |path_segment, child|
      walk_yaml(child, [*path, path_segment], active_containers: active_containers, &block)
    end
    active_containers.delete(value) if container
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

  def top_level_permissions_violation(path, workflow)
    filename = File.basename(path)
    expected = approved_top_level_permissions[filename]
    return "#{filename}: top-level permissions are not registered" unless expected
    return if workflow["permissions"] == expected

    "#{filename}: top-level permissions must equal #{expected.inspect}; got #{workflow['permissions'].inspect}"
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
              - "uses": "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1" # v7.0.1
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
            - uses: Owner/Repository/subpath@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
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
              - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
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
    pinned_action = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
    unsafe_documents = {
      "aliased-value" => <<~YAML,
        metadata:
          action: &action #{pinned_action}
        jobs:
          build:
            steps:
              - uses: *action # v7.0.1
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
              - <<: *defaults # v7.0.1
      YAML
      "duplicate-value" => <<~YAML,
        jobs:
          build:
            steps:
              - uses: #{pinned_action} # v7.0.1
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
              - { uses: #{pinned_action} } # v7.0.1
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
                  uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
              - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
      YAML

      expect(external_action_policy_violations(path)).to include(match(%r{actions/checkout@3d3c42e5aac5}))
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

  it "walks a shared aliased container at each non-recursive path" do
    document = YAML.safe_load(<<~YAML, aliases: true)
      shared: &shared
        run: echo "${{ github.ref }}"
      jobs:
        first:
          steps:
            - *shared
        second:
          steps:
            - *shared
    YAML

    walked_paths = []
    walk_yaml(document) { |_value, yaml_path| walked_paths << yaml_path }

    expect(walked_paths).to include(
      ["jobs", "first", "steps", 0, "run"],
      ["jobs", "second", "steps", 0, "run"]
    )
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

  it "rejects top-level workflow permissions outside the exact approved map" do
    workflow = { "permissions" => { "contents" => "write" } }

    expect(top_level_permissions_violation("rspec.yml", workflow)).to include("must equal")
  end

  it "uses least-privilege workflow defaults and never persists checkout credentials" do
    expect(workflow_files.map { |path| File.basename(path) }.sort).to eq(approved_top_level_permissions.keys.sort)

    violations = workflow_files.flat_map do |path|
      workflow = YAML.safe_load_file(path, aliases: true)
      file_violations = []
      permissions_violation = top_level_permissions_violation(path, workflow)
      file_violations << permissions_violation if permissions_violation

      walk_yaml(workflow) do |value, yaml_path|
        next unless value.is_a?(Hash) && value["uses"]&.start_with?("actions/checkout@")
        next if value.dig("with", "persist-credentials") == false

        file_violations << "#{File.basename(path)}: #{yaml_path.join('.')} persists checkout credentials"
      end

      file_violations
    end

    expect(violations).to be_empty, violations.join("\n")
  end

  describe "generated GitHub flow templates" do
    def template_root
      File.expand_path("../lib/github_flow_templates", __dir__)
    end

    def checkout_constant_file
      File.join(template_root, "bin/test-cpflow-github-flow")
    end

    def template_pin_scripts
      %w[pin-cpflow-github-ref test-cpflow-github-flow].map { |name| File.join(template_root, "bin", name) }
    end

    # Only the generated workflows and the two generated scripts carry action pins. Markdown under
    # the templates root documents illustrative YAML, so a code fence must never fail the guard.
    def template_pin_files
      workflows = Dir.glob(File.join(template_root, ".github/**/*.{yml,yaml}"))

      (workflows + template_pin_scripts).select { |path| File.file?(path) }.sort
    end

    # EXPECTED_CPFLOW_CHECKOUT_ACTION has its own scan, so the constant file stays out of the
    # generic `uses:` scan and a future heredoc line cannot be reported twice.
    def template_workflow_scan_files
      template_pin_files - [checkout_constant_file]
    end

    # The four places that must move together whenever an external action pin is bumped.
    def pin_update_sites
      [
        ".github/workflows/** and .github/actions/**",
        "lib/github_flow_templates/.github/workflows/**",
        "lib/github_flow_templates/bin/test-cpflow-github-flow (EXPECTED_CPFLOW_CHECKOUT_ACTION)",
        "spec/command/generate_github_actions_spec.rb / spec/github_workflows_spec.rb (pinned SHA assertions)"
      ]
    end

    # Anchored to a real YAML step key so a commented-out line or `uses:` text inside a `run: |`
    # block cannot masquerade as a pin.
    def action_pin_pattern
      %r{
        \A\s*-?\s*(?<key_quote>["']?)uses\k<key_quote>:\s*(?<quote>["']?)
        (?<action>[\w.-]+/[\w./-]+)@(?<ref>[^\s"'\#]+)\k<quote>
        (?:\s*\#\s*(?<version>\S+))?
      }x
    end

    def docker_pin_pattern
      %r{
        \A\s*-?\s*(?<key_quote>["']?)uses\k<key_quote>:\s*(?<quote>["']?)
        (?<image>docker://[^\s"'\#@]+)(?:@(?<digest>[^\s"'\#]+))?\k<quote>
      }x
    end

    def checkout_constant_pattern
      %r{\AEXPECTED_CPFLOW_CHECKOUT_ACTION\s*=\s*"(?<action>[\w.-]+/[\w./-]+)@(?<ref>[^\s"]+)"}
    end

    def commented_line?(line)
      line.lstrip.start_with?("#")
    end

    def immutable_ref?(entry)
      return entry[:ref].to_s.match?(/\Asha256:[0-9a-f]{64}\z/) if entry[:kind] == :docker

      entry[:ref].to_s.match?(/\A[0-9a-f]{40}\z/)
    end

    def required_ref_description(entry)
      entry[:kind] == :docker ? "an immutable sha256:<64-hex> image digest" : "a 40-hex commit SHA"
    end

    def trusted_action_identity(action)
      action.split("/").first(2).join("/").downcase
    end

    def relative_repo_path(path)
      Pathname(path).relative_path_from(Pathname(__dir__).parent).to_s
    end

    # Generated files may carry non-UTF-8 bytes; scrub them instead of raising ArgumentError.
    def read_lines(path)
      File.binread(path).force_encoding(Encoding::UTF_8).scrub("").lines
    end

    def build_entry(**attributes)
      reference = attributes.fetch(:reference)
      version = attributes.fetch(:version)

      attributes.merge(pin: version ? "#{reference} # #{version}" : reference)
    end

    def action_entries(path, version_optional: false)
      read_lines(path).each_with_index.filter_map do |line, index|
        next if commented_line?(line)

        source = "#{relative_repo_path(path)}:#{index + 1}"
        repository_entry(line, source, version_optional: version_optional) || docker_entry(line, source)
      end
    end

    # Local `./.github/actions/*` steps and cpflow's own cross-repository reusable workflow calls
    # (`@__CPFLOW_GITHUB_ACTIONS_REF__`, `@vX.Y.Z`) are not external pins. Everything else is kept,
    # mutable refs included, so they are reported as violations rather than silently dropped.
    def repository_entry(line, source, version_optional:)
      match = line.match(action_pin_pattern)
      return unless match

      identity = trusted_action_identity(match[:action])
      return if match[:action].start_with?("./") || identity == "shakacode/control-plane-flow"

      build_entry(kind: :repository, identity: identity, reference: "#{match[:action]}@#{match[:ref]}",
                  ref: match[:ref], version: match[:version], version_optional: version_optional, source: source)
    end

    def docker_entry(line, source)
      match = line.match(docker_pin_pattern)
      return unless match

      reference = [match[:image], match[:digest] && "@#{match[:digest]}"].compact.join
      build_entry(kind: :docker, identity: match[:image], reference: reference, ref: match[:digest],
                  version: nil, version_optional: true, source: source)
    end

    def constant_entries(path)
      read_lines(path).each_with_index.filter_map do |line, index|
        match = line.match(checkout_constant_pattern)
        next unless match

        build_entry(kind: :repository, identity: trusted_action_identity(match[:action]), version: nil,
                    reference: "#{match[:action]}@#{match[:ref]}", ref: match[:ref],
                    version_optional: true, source: "#{relative_repo_path(path)}:#{index + 1}")
      end
    end

    def format_action_entries(entries)
      entries.group_by { |entry| entry[:pin] }.map do |pin, grouped|
        extra = grouped.length > 1 ? " and #{grouped.length - 1} more" : ""
        "#{pin} (#{grouped.first[:source]}#{extra})"
      end.join("; ")
    end

    def mutable_ref_violations(entries)
      entries.reject { |entry| immutable_ref?(entry) }.map do |entry|
        "#{entry[:source]}: #{entry[:reference]} is not pinned to #{required_ref_description(entry)}"
      end
    end

    def template_only_violations(repository_identities, template_entries)
      pinned = template_entries.select { |entry| immutable_ref?(entry) }
      unmatched = pinned.reject { |entry| repository_identities.include?(entry[:identity]) }

      unmatched.group_by { |entry| entry[:identity] }.map do |identity, grouped|
        "#{identity} is pinned only by the generated templates (#{format_action_entries(grouped)}) and has no " \
          "reviewed counterpart in the repository workflows"
      end
    end

    def inconsistent_repository_pin(identity, repository_entries)
      return if repository_entries.map { |entry| entry[:pin] }.uniq.one?

      "#{identity} is pinned inconsistently inside the repository workflows: " \
        "#{format_action_entries(repository_entries)}"
    end

    # Only EXPECTED_CPFLOW_CHECKOUT_ACTION and `docker://` images may omit the version comment;
    # neither is a workflow step with somewhere to hang a same-line release tag.
    def matching_version_comment?(canonical, entry)
      return true if entry[:version] == canonical[:version]

      entry[:version_optional] && entry[:version].nil?
    end

    def entry_drift_violations(canonical, entries)
      entries.filter_map do |entry|
        next if entry[:ref] == canonical[:ref] && matching_version_comment?(canonical, entry)

        "#{entry[:source]}: #{entry[:pin]} does not match the repository pin " \
          "#{canonical[:pin]} (#{canonical[:source]})"
      end
    end

    def identity_pin_violations(repository_by_identity, entries)
      pinned = entries.select { |entry| immutable_ref?(entry) }

      pinned.group_by { |entry| entry[:identity] }.flat_map do |identity, grouped|
        repository_entries = repository_by_identity[identity]
        next [] unless repository_entries

        inconsistent = inconsistent_repository_pin(identity, repository_entries)
        next [inconsistent] if inconsistent

        entry_drift_violations(repository_entries.first, grouped)
      end
    end

    def pin_guard_violations(repository_entries, template_entries)
      pinned_repository = repository_entries.select { |entry| immutable_ref?(entry) }
      identities = repository_entries.map { |entry| entry[:identity] }.uniq
      all_entries = repository_entries + template_entries

      mutable_ref_violations(all_entries) +
        template_only_violations(identities, template_entries) +
        identity_pin_violations(pinned_repository.group_by { |entry| entry[:identity] }, all_entries)
    end

    def pin_guard_failure_message(violations)
      <<~MESSAGE
        Generated template action pins must match the reviewed repository workflow pins:
          - #{violations.join("\n  - ")}
        Bump the commit SHA and the version comment in all four places together:
          - #{pin_update_sites.join("\n  - ")}
      MESSAGE
    end

    def synthetic_entry(source, ref, version, identity: "actions/checkout", version_optional: false)
      build_entry(kind: :repository, identity: identity, reference: "#{identity}@#{ref}", ref: ref,
                  version: version, version_optional: version_optional, source: source)
    end

    def synthetic_docker_entry(source, image, digest = nil)
      build_entry(kind: :docker, identity: image, reference: digest ? "#{image}@#{digest}" : image,
                  ref: digest, version: nil, version_optional: true, source: source)
    end

    it "reports every drift class with the four places to fix them" do
      repository_entries = [
        synthetic_entry(".github/workflows/rspec.yml:57", "a" * 40, "v7.0.1"),
        synthetic_docker_entry(".github/workflows/rspec.yml:60", "docker://alpine", "sha256:#{'a' * 64}")
      ]
      template_entries = [
        synthetic_entry("lib/github_flow_templates/.github/workflows/promote.yml:64", "v7", "v7.0.1"),
        synthetic_entry("lib/github_flow_templates/.github/workflows/promote.yml:69", "a" * 40, nil),
        synthetic_entry("lib/github_flow_templates/bin/test-cpflow-github-flow:108", "a" * 40, nil,
                        version_optional: true),
        synthetic_entry("lib/github_flow_templates/.github/workflows/promote.yml:80", "c" * 40, "v1.0.0",
                        identity: "some/other-action"),
        synthetic_docker_entry("lib/github_flow_templates/.github/workflows/promote.yml:90",
                               "docker://alpine:latest"),
        synthetic_docker_entry("lib/github_flow_templates/.github/workflows/promote.yml:95",
                               "docker://alpine", "sha256:#{'b' * 64}")
      ]

      violations = pin_guard_violations(repository_entries, template_entries)

      expect(violations).to contain_exactly(
        a_string_including("promote.yml:64", "is not pinned to a 40-hex commit SHA"),
        a_string_including("promote.yml:69", "does not match the repository pin"),
        a_string_including("some/other-action", "pinned only by the generated templates"),
        a_string_including("promote.yml:90", "docker://alpine:latest", "sha256:<64-hex> image digest"),
        a_string_including("promote.yml:95", "does not match the repository pin")
      )
      expect(pin_guard_failure_message(violations)).to include(
        "lib/github_flow_templates/.github/workflows/promote.yml:69", ".github/workflows/rspec.yml:57",
        *pin_update_sites
      )
    end

    it "ignores commented-out and embedded-script uses lines" do
      Dir.mktmpdir("template-pin-guard") do |directory|
        path = Pathname(directory).join("noise.yml")
        path.write(<<~YAML)
          jobs:
            build:
              steps:
                # uses: evil/action@#{'d' * 40} # v9.9.9
                - run: |
                    echo "uses: evil/action@#{'d' * 40} # v9.9.9"
                - uses: actions/checkout@#{'a' * 40} # v7.0.1
        YAML

        entries = action_entries(path)

        expect(entries.map { |entry| entry[:reference] }).to eq(["actions/checkout@#{'a' * 40}"])
        expect(entries.map { |entry| entry[:source] }).to all(end_with("noise.yml:7"))
      end
    end

    it "reads generated files with invalid UTF-8 bytes instead of raising" do
      Dir.mktmpdir("template-pin-guard") do |directory|
        path = Pathname(directory).join("binary.yml")
        path.binwrite("- uses: actions/checkout@#{'a' * 40} # v7.0.1\n")
        path.open("ab") { |file| file.write([0xC3, 0x28, 0x0A].pack("C*")) }

        expect(action_entries(path).map { |entry| entry[:pin] }).to(
          eq(["actions/checkout@#{'a' * 40} # v7.0.1"])
        )
      end
    end

    it "scans only the generated workflows and scripts, so markdown examples cannot fail the guard" do
      scanned = template_pin_files.map { |path| relative_repo_path(path) }

      expect(scanned).to include(
        "lib/github_flow_templates/.github/workflows/cpflow-promote-staging-to-production.yml",
        "lib/github_flow_templates/bin/pin-cpflow-github-ref",
        "lib/github_flow_templates/bin/test-cpflow-github-flow"
      )
      expect(scanned.grep(/\.(?:md|markdown)\z/)).to be_empty
      expect(File).to exist(File.join(template_root, ".github/cpflow-help.md"))

      Dir.mktmpdir("template-pin-guard") do |directory|
        sample = Pathname(directory).join("cpflow-help.md")
        sample.write("Example workflow:\n\n```yaml\n- uses: example/action@v1\n```\n")

        expect(mutable_ref_violations(action_entries(sample))).not_to be_empty
      end
    end

    it "pins the same commits and version comments as the repository workflows" do
      constant = constant_entries(checkout_constant_file)
      expect(constant.map { |entry| entry[:identity] }).to(
        eq(["actions/checkout"]),
        "EXPECTED_CPFLOW_CHECKOUT_ACTION is no longer discoverable in " \
        "#{relative_repo_path(checkout_constant_file)}"
      )

      repository_entries = action_files.flat_map { |path| action_entries(path) }
      template_entries = template_workflow_scan_files.flat_map { |path| action_entries(path) } + constant
      expect(repository_entries.map { |entry| entry[:identity] }.uniq).to(
        include("actions/checkout", "docker/setup-buildx-action")
      )
      expect(template_entries.map { |entry| entry[:identity] }.uniq).to(
        include("actions/checkout", "docker/setup-buildx-action")
      )

      violations = pin_guard_violations(repository_entries, template_entries)
      expect(violations).to be_empty, pin_guard_failure_message(violations)
    end
  end
end
