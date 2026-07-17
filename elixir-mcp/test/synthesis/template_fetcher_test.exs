# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.TemplateFetcherTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Synthesis.TemplateCache
  alias FeedbackATron.Synthesis.TemplateFetcher

  # Full GitHub issue form exercising every block type.
  @bug_yaml """
  name: Bug Report
  description: File a bug report
  title: "[Bug]: "
  labels:
    - bug
    - triage
  body:
    - type: markdown
      attributes:
        value: |
          Thanks for taking the time to fill out this bug report!
    - type: input
      id: contact
      attributes:
        label: Contact Details
        description: How can we get in touch?
        placeholder: ex. email@example.com
      validations:
        required: false
    - type: textarea
      id: what-happened
      attributes:
        label: What happened?
        description: Also tell us, what did you expect to happen?
        placeholder: Tell us what you see!
      validations:
        required: true
    - type: dropdown
      id: version
      attributes:
        label: Version
        options:
          - 1.0.2
          - 1.0.3
      validations:
        required: true
    - type: checkboxes
      id: terms
      attributes:
        label: Code of Conduct
        options:
          - label: I agree to follow this project's Code of Conduct
            required: true
  """

  @feature_yaml """
  name: Feature Request
  description: Suggest an idea
  labels: enhancement
  body:
    - type: textarea
      id: idea
      attributes:
        label: Describe the feature
      validations:
        required: true
  """

  setup do
    # TemplateCache is started by the application; fall back to a
    # supervised instance when running without it.
    case Process.whereis(TemplateCache) do
      nil -> start_supervised!(TemplateCache)
      _pid -> :ok
    end

    :ok = TemplateCache.purge()
    :ok
  end

  # ---------------------------------------------------------------------------
  # parse_form/2
  # ---------------------------------------------------------------------------

  describe "parse_form/2" do
    test "parses a full bug.yml with every block type" do
      assert {:ok, form} = TemplateFetcher.parse_form(@bug_yaml, "bug.yml")

      assert form.name == "Bug Report"
      assert form.file == "bug.yml"
      assert form.description == "File a bug report"
      assert form.title == "[Bug]: "
      assert form.labels == ["bug", "triage"]

      assert Enum.map(form.fields, & &1.type) ==
               [:markdown, :input, :textarea, :dropdown, :checkboxes]

      assert Enum.map(form.fields, & &1.id) ==
               ["md-0", "contact", "what-happened", "version", "terms"]

      [_md, contact, what, version, terms] = form.fields

      assert contact.label == "Contact Details"
      assert contact.description == "How can we get in touch?"
      assert contact.placeholder == "ex. email@example.com"
      assert contact.options == []

      assert what.label == "What happened?"
      assert what.placeholder == "Tell us what you see!"

      # 1.0.2 / 1.0.3 are not valid YAML floats, so they stay strings.
      assert version.options == ["1.0.2", "1.0.3"]

      # Checkbox options are maps; the label is extracted and stringified.
      assert terms.options == ["I agree to follow this project's Code of Conduct"]
    end

    test "extracts required from validations" do
      assert {:ok, form} = TemplateFetcher.parse_form(@bug_yaml, "bug.yml")

      required_by_id = Map.new(form.fields, fn f -> {f.id, f.required} end)

      assert required_by_id["contact"] == false
      assert required_by_id["what-happened"] == true
      assert required_by_id["version"] == true
      assert required_by_id["terms"] == false
    end

    test "keeps markdown blocks but forces required: false and generates ids" do
      yaml = """
      name: Docs
      body:
        - type: markdown
          attributes:
            value: Read the manual first.
          validations:
            required: true
        - type: input
          id: page
          attributes:
            label: Page
      """

      assert {:ok, form} = TemplateFetcher.parse_form(yaml, "docs.yml")
      [markdown, _input] = form.fields

      assert markdown.type == :markdown
      assert markdown.id == "md-0"
      # Even a bogus validations.required=true on markdown is ignored.
      assert markdown.required == false
    end

    test "falls back to slugified label when a field has no id" do
      yaml = """
      name: No IDs
      body:
        - type: input
          attributes:
            label: "Contact Details!"
      """

      assert {:ok, form} = TemplateFetcher.parse_form(yaml, "noids.yml")
      assert [%{id: "contact-details", type: :input}] = form.fields
    end

    test "maps unknown block types to :input" do
      yaml = """
      name: Odd
      body:
        - type: slider
          id: level
          attributes:
            label: Level
      """

      assert {:ok, form} = TemplateFetcher.parse_form(yaml, "odd.yml")
      assert [%{id: "level", type: :input}] = form.fields
    end

    test "missing body key is rejected" do
      yaml = """
      name: Bodyless
      description: no body here
      """

      assert {:error, :invalid_template} = TemplateFetcher.parse_form(yaml, "bodyless.yml")
    end

    test "non-map YAML is rejected" do
      yaml = """
      - just
      - a list
      """

      assert {:error, :invalid_template} = TemplateFetcher.parse_form(yaml, "list.yml")
    end

    test "oversize input is rejected before parsing" do
      # 131_073 bytes — one over the 131_072 limit.
      huge = "name: Big\nbody: []\n# " <> String.duplicate("a", 131_073)

      assert {:error, :template_too_large} = TemplateFetcher.parse_form(huge, "big.yml")
    end

    test "malformed YAML returns a yaml_error tuple" do
      assert {:error, {:yaml_error, message}} =
               TemplateFetcher.parse_form("name: [unclosed", "broken.yml")

      assert is_binary(message)
    end

    test "unquoted YAML boolean-ish dropdown options are stringified" do
      yaml = """
      name: Booleans
      body:
        - type: dropdown
          id: choice
          attributes:
            label: Choice
            options:
              - yes
              - no
              - true
              - false
      """

      assert {:ok, form} = TemplateFetcher.parse_form(yaml, "bool.yml")
      [field] = form.fields

      # Verified empirically against yaml_elixir 2.x (yamerl): it resolves
      # scalars with the YAML 1.2 core schema, NOT YAML 1.1 extended
      # booleans. Unquoted `yes`/`no` therefore stay the strings
      # "yes"/"no", while unquoted `true`/`false` become booleans and are
      # stringified by to_string/1 to "true"/"false".
      assert field.options == ["yes", "no", "true", "false"]
    end
  end

  # ---------------------------------------------------------------------------
  # fetch/2 via Bypass
  # ---------------------------------------------------------------------------

  describe "fetch/2" do
    setup do
      bypass = Bypass.open()
      base = "http://localhost:#{bypass.port}"
      {:ok, bypass: bypass, base: base}
    end

    test "lists, fetches, parses and caches templates", %{bypass: bypass, base: base} do
      repo = "acme/widget"

      listing = [
        %{"name" => "bug.yml", "type" => "file"},
        %{"name" => "feature.yaml", "type" => "file"},
        %{"name" => "config.yml", "type" => "file"},
        %{"name" => "PULL_REQUEST_TEMPLATE.md", "type" => "file"}
      ]

      Bypass.expect_once(
        bypass,
        "GET",
        "/repos/acme/widget/contents/.github/ISSUE_TEMPLATE",
        fn conn ->
          assert {"accept", "application/vnd.github+json"} in conn.req_headers

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(listing))
        end
      )

      Bypass.expect_once(
        bypass,
        "GET",
        "/acme/widget/HEAD/.github/ISSUE_TEMPLATE/bug.yml",
        fn conn ->
          Plug.Conn.resp(conn, 200, @bug_yaml)
        end
      )

      Bypass.expect_once(
        bypass,
        "GET",
        "/acme/widget/HEAD/.github/ISSUE_TEMPLATE/feature.yaml",
        fn conn ->
          Plug.Conn.resp(conn, 200, @feature_yaml)
        end
      )

      assert {:ok, [bug, feature]} =
               TemplateFetcher.fetch(repo, base_url: base, raw_base_url: base)

      assert bug.name == "Bug Report"
      assert bug.file == "bug.yml"
      assert feature.name == "Feature Request"
      assert feature.file == "feature.yaml"
      # labels as a single string is normalized to a one-element list.
      assert feature.labels == ["enhancement"]

      # Second fetch is served from the cache — Bypass.expect_once would
      # fail this test if any endpoint were hit again.
      assert {:ok, [^bug, ^feature]} =
               TemplateFetcher.fetch(repo, base_url: base, raw_base_url: base)

      assert {:ok, ^bug} = TemplateCache.get({repo, "bug.yml"})
    end

    test "404 on the template directory yields :no_templates", %{bypass: bypass, base: base} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/repos/acme/empty/contents/.github/ISSUE_TEMPLATE",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(404, ~s({"message": "Not Found"}))
        end
      )

      assert {:error, :no_templates} =
               TemplateFetcher.fetch("acme/empty", base_url: base, raw_base_url: base)
    end

    test "listing with no template files yields :no_templates", %{bypass: bypass, base: base} do
      listing = [%{"name" => "config.yml", "type" => "file"}]

      Bypass.expect_once(
        bypass,
        "GET",
        "/repos/acme/cfgonly/contents/.github/ISSUE_TEMPLATE",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(listing))
        end
      )

      assert {:error, :no_templates} =
               TemplateFetcher.fetch("acme/cfgonly", base_url: base, raw_base_url: base)
    end

    test "non-JSON listing body yields an error tuple", %{bypass: bypass, base: base} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/repos/acme/htmlwall/contents/.github/ISSUE_TEMPLATE",
        fn conn ->
          Plug.Conn.resp(conn, 200, "<html>definitely not json</html>")
        end
      )

      assert {:error, {:unexpected_response, _body}} =
               TemplateFetcher.fetch("acme/htmlwall", base_url: base, raw_base_url: base)
    end

    test "rejects non-loopback plain-HTTP base URLs" do
      assert {:error, {:insecure_base_url, _}} =
               TemplateFetcher.fetch("acme/widget", base_url: "http://evil.example.com")

      assert {:error, {:insecure_base_url, _}} =
               TemplateFetcher.fetch_form("acme/widget", "bug.yml",
                 raw_base_url: "http://evil.example.com"
               )
    end
  end

  # ---------------------------------------------------------------------------
  # fetch_form/3 via Bypass
  # ---------------------------------------------------------------------------

  describe "fetch_form/3" do
    setup do
      bypass = Bypass.open()
      base = "http://localhost:#{bypass.port}"
      {:ok, bypass: bypass, base: base}
    end

    test "fetches a single form and caches it", %{bypass: bypass, base: base} do
      repo = "acme/single"

      Bypass.expect_once(
        bypass,
        "GET",
        "/acme/single/HEAD/.github/ISSUE_TEMPLATE/bug.yml",
        fn conn ->
          Plug.Conn.resp(conn, 200, @bug_yaml)
        end
      )

      assert {:ok, form} = TemplateFetcher.fetch_form(repo, "bug.yml", raw_base_url: base)
      assert form.name == "Bug Report"

      # Cache hit — no second HTTP request (expect_once enforces this).
      assert {:ok, ^form} = TemplateFetcher.fetch_form(repo, "bug.yml", raw_base_url: base)
    end

    test "missing file yields :not_found", %{bypass: bypass, base: base} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/acme/single/HEAD/.github/ISSUE_TEMPLATE/nope.yml",
        fn conn ->
          Plug.Conn.resp(conn, 404, "404: Not Found")
        end
      )

      assert {:error, :not_found} =
               TemplateFetcher.fetch_form("acme/single", "nope.yml", raw_base_url: base)
    end
  end

  # ---------------------------------------------------------------------------
  # TemplateCache TTL
  # ---------------------------------------------------------------------------

  describe "TemplateCache" do
    test "get/put round-trip and purge" do
      assert :miss = TemplateCache.get({"a/b", :list})
      assert :ok = TemplateCache.put({"a/b", :list}, [:form])
      assert {:ok, [:form]} = TemplateCache.get({"a/b", :list})

      assert :ok = TemplateCache.purge()
      assert :miss = TemplateCache.get({"a/b", :list})
    end

    test "entries older than 900s are misses" do
      stale = System.monotonic_time(:second) - 901
      assert :ok = TemplateCache.put_at({"a/b", "bug.yml"}, %{name: "old"}, stale)

      assert :miss = TemplateCache.get({"a/b", "bug.yml"})
    end
  end
end
