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

    def template_pin_files
      # FNM_DOTMATCH is required: the generated templates live under a dot directory (`.github`).
      Dir.glob(File.join(template_root, "**/*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.sort
    end

    def checkout_constant_file
      File.join(template_root, "bin/test-cpflow-github-flow")
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

    def checkout_constant_pattern
      %r{\AEXPECTED_CPFLOW_CHECKOUT_ACTION\s*=\s*"(?<action>[\w.-]+/[\w./-]+)@(?<ref>[^\s"]+)"}
    end

    def commented_line?(line)
      line.lstrip.start_with?("#")
    end

    def commit_pinned?(entry)
      entry[:ref].match?(/\A[0-9a-f]{40}\z/)
    end

    def trusted_action_identity(action)
      action.split("/").first(2).join("/").downcase
    end

    def relative_repo_path(path)
      Pathname(path).relative_path_from(Pathname(__dir__).parent).to_s
    end

    def action_entries(path, pattern = action_pin_pattern, version_optional: false)
      File.readlines(path).each_with_index.filter_map do |line, index|
        next if commented_line?(line)

        match = line.match(pattern)
        next unless match

        build_action_entry(match, path, index + 1, version_optional: version_optional)
      end
    end

    # Local `./.github/actions/*` steps and cpflow's own cross-repository reusable workflow calls
    # (`@__CPFLOW_GITHUB_ACTIONS_REF__`, `@vX.Y.Z`) are not external action pins. Every other
    # external `uses:` entry is kept, including mutable refs, so they can be reported as violations.
    def build_action_entry(match, path, line_number, version_optional:)
      action = match[:action]
      identity = trusted_action_identity(action)
      return if action.start_with?("./") || identity == "shakacode/control-plane-flow"

      version = match.names.include?("version") ? match[:version] : nil
      {
        identity: identity, action: action, ref: match[:ref], version: version,
        version_optional: version_optional, source: "#{relative_repo_path(path)}:#{line_number}",
        pin: [action, "@", match[:ref], version ? " # #{version}" : ""].join
      }
    end

    def format_action_entries(entries)
      entries.group_by { |entry| entry[:pin] }.map do |pin, grouped|
        extra = grouped.length > 1 ? " and #{grouped.length - 1} more" : ""
        "#{pin} (#{grouped.first[:source]}#{extra})"
      end.join("; ")
    end

    def mutable_ref_violations(entries)
      entries.reject { |entry| commit_pinned?(entry) }.map do |entry|
        "#{entry[:source]}: #{entry[:action]}@#{entry[:ref]} is not pinned to a 40-hex commit SHA"
      end
    end

    def template_only_violations(repository_identities, template_entries)
      unmatched = template_entries.reject { |entry| repository_identities.include?(entry[:identity]) }

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

    # Only EXPECTED_CPFLOW_CHECKOUT_ACTION may omit the version comment; it is a Ruby constant,
    # not a workflow step, so there is nowhere to hang a same-line release tag.
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
      pinned = entries.select { |entry| commit_pinned?(entry) }

      pinned.group_by { |entry| entry[:identity] }.flat_map do |identity, grouped|
        repository_entries = repository_by_identity[identity]
        next [] unless repository_entries

        inconsistent = inconsistent_repository_pin(identity, repository_entries)
        next [inconsistent] if inconsistent

        entry_drift_violations(repository_entries.first, grouped)
      end
    end

    def pin_guard_violations(repository_entries, template_entries)
      repository_by_identity = repository_entries.group_by { |entry| entry[:identity] }
      all_entries = repository_entries + template_entries

      mutable_ref_violations(all_entries) +
        template_only_violations(repository_by_identity.keys, template_entries) +
        identity_pin_violations(repository_by_identity, all_entries)
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
      {
        identity: identity, action: identity, ref: ref, version: version,
        version_optional: version_optional, source: source,
        pin: [identity, "@", ref, version ? " # #{version}" : ""].join
      }
    end

    it "reports mutable refs, comment drift, and template-only actions with the four places to fix them" do
      repository_entries = [synthetic_entry(".github/workflows/rspec.yml:57", "a" * 40, "v7.0.1")]
      template_entries = [
        synthetic_entry("lib/github_flow_templates/.github/workflows/promote.yml:64", "v7", "v7.0.1"),
        synthetic_entry("lib/github_flow_templates/.github/workflows/promote.yml:69", "a" * 40, nil),
        synthetic_entry("lib/github_flow_templates/bin/test-cpflow-github-flow:108", "a" * 40, nil,
                        version_optional: true),
        synthetic_entry("lib/github_flow_templates/.github/workflows/promote.yml:80", "c" * 40, "v1.0.0",
                        identity: "some/other-action")
      ]

      violations = pin_guard_violations(repository_entries, template_entries)

      expect(violations).to contain_exactly(
        a_string_including("promote.yml:64", "is not pinned to a 40-hex commit SHA"),
        a_string_including("promote.yml:69", "does not match the repository pin"),
        a_string_including("some/other-action", "pinned only by the generated templates")
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

        expect(entries.map { |entry| entry[:action] }).to eq(["actions/checkout"])
        expect(entries.map { |entry| entry[:source] }).to all(end_with("noise.yml:7"))
      end
    end

    it "pins the same commits and version comments as the repository workflows" do
      constant_entries = action_entries(checkout_constant_file, checkout_constant_pattern, version_optional: true)
      expect(constant_entries.map { |entry| entry[:identity] }).to(
        eq(["actions/checkout"]),
        "EXPECTED_CPFLOW_CHECKOUT_ACTION is no longer discoverable in " \
        "#{relative_repo_path(checkout_constant_file)}"
      )

      repository_entries = action_files.flat_map { |path| action_entries(path) }
      template_entries = template_pin_files.flat_map { |path| action_entries(path) } + constant_entries
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
