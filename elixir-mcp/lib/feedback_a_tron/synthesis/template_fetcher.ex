# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Synthesis.TemplateFetcher do
  @moduledoc """
  Fetches and parses GitHub issue-form templates for a repository.

  Feedback is *shaped for the receiver*: their template, their taxonomy,
  only what is needed. This module retrieves the receiver's own issue
  forms (`.github/ISSUE_TEMPLATE/*.yml`) so downstream synthesis can fill
  in exactly the fields the maintainers asked for.

  Templates are listed via the GitHub contents API and fetched raw from
  `raw.githubusercontent.com`, then parsed into the shared `form` shape:

      form  = %{name, file, description, labels, title, fields}
      field = %{id, type, label, description, placeholder, options, required, render}

  All fetches go through `FeedbackATron.Synthesis.TemplateCache`
  (keys `{repo, :list}` and `{repo, file}`, 15-minute TTL) so repeated
  synthesis runs against the same repo do not hammer the forge.

  `opts[:base_url]` / `opts[:raw_base_url]` override the API and raw
  hosts (tests point them at Bypass). Overrides must be HTTPS, except
  plain-HTTP loopback (`http://localhost`, `http://127.0.0.1`) which
  Bypass requires.
  """

  require Logger

  alias FeedbackATron.Synthesis.TemplateCache

  @api_base "https://api.github.com"
  @raw_base "https://raw.githubusercontent.com"
  @template_dir ".github/ISSUE_TEMPLATE"

  # GitHub caps issue templates well below this; anything larger is
  # malformed or hostile input, not a template.
  @max_template_bytes 131_072

  @block_types %{
    "input" => :input,
    "textarea" => :textarea,
    "dropdown" => :dropdown,
    "checkboxes" => :checkboxes,
    "markdown" => :markdown
  }

  @doc """
  Fetch and parse every issue-form template for `repo` (`"owner/repo"`).

  Returns `{:ok, [form]}` or `{:error, :no_templates}` when the template
  directory is missing (404), empty, or contains no parseable forms.
  Unparsable files are skipped with a logged warning rather than failing
  the whole fetch.
  """
  def fetch(repo, opts \\ []) when is_binary(repo) do
    case TemplateCache.get({repo, :list}) do
      {:ok, forms} ->
        {:ok, forms}

      :miss ->
        with {:ok, base_url} <- validate_base_url(Keyword.get(opts, :base_url, @api_base)),
             {:ok, raw_base_url} <-
               validate_base_url(Keyword.get(opts, :raw_base_url, @raw_base)),
             {:ok, files} <- list_template_files(base_url, repo) do
          case fetch_and_parse_all(raw_base_url, repo, files) do
            [] ->
              {:error, :no_templates}

            forms ->
              TemplateCache.put({repo, :list}, forms)
              {:ok, forms}
          end
        end
    end
  end

  @doc """
  Fetch and parse a single template file for `repo`, through the cache.

  Returns `{:ok, form}` or `{:error, term}`.
  """
  def fetch_form(repo, file, opts \\ []) when is_binary(repo) and is_binary(file) do
    case TemplateCache.get({repo, file}) do
      {:ok, form} ->
        {:ok, form}

      :miss ->
        with {:ok, raw_base_url} <-
               validate_base_url(Keyword.get(opts, :raw_base_url, @raw_base)),
             {:ok, yaml} <- fetch_raw(raw_base_url, repo, file),
             {:ok, form} <- parse_form(yaml, file) do
          TemplateCache.put({repo, file}, form)
          {:ok, form}
        end
    end
  end

  @doc """
  Parse an issue-form YAML document into the shared `form` shape.

  Requires a YAML map with a `"name"` string and a `"body"` list.
  Returns `{:ok, form}`, `{:error, :invalid_template}`,
  `{:error, :template_too_large}` for inputs over #{@max_template_bytes}
  bytes, or `{:error, {:yaml_error, message}}` for unparseable YAML.
  """
  def parse_form(yaml_string, file) when is_binary(yaml_string) and is_binary(file) do
    if byte_size(yaml_string) > @max_template_bytes do
      {:error, :template_too_large}
    else
      case safe_yaml(yaml_string) do
        {:ok, doc} when is_map(doc) ->
          if is_binary(doc["name"]) and is_list(doc["body"]) do
            {:ok, build_form(doc, file)}
          else
            {:error, :invalid_template}
          end

        {:ok, _not_a_map} ->
          {:error, :invalid_template}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # HTTP
  # ---------------------------------------------------------------------------

  defp list_template_files(base_url, repo) do
    url = "#{base_url}/repos/#{repo}/contents/#{@template_dir}"

    case Req.get(url, headers: api_headers()) do
      {:ok, %{status: 200, body: entries}} when is_list(entries) ->
        files =
          for %{"name" => name} <- entries, template_file?(name), do: name

        if files == [], do: {:error, :no_templates}, else: {:ok, files}

      {:ok, %{status: 404}} ->
        {:error, :no_templates}

      {:ok, %{status: 200, body: other}} ->
        {:error, {:unexpected_response, other}}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:network_error, inspect(reason)}}
    end
  end

  defp fetch_and_parse_all(raw_base_url, repo, files) do
    {forms, errors} =
      Enum.reduce(files, {[], []}, fn file, {forms, errors} ->
        case cached_fetch_form(raw_base_url, repo, file) do
          {:ok, form} -> {[form | forms], errors}
          {:error, reason} -> {forms, [{file, reason} | errors]}
        end
      end)

    for {file, reason} <- Enum.reverse(errors) do
      Logger.warning(
        "TemplateFetcher: skipping unparsable template #{repo}/#{file}: #{inspect(reason)}"
      )
    end

    Enum.reverse(forms)
  end

  defp cached_fetch_form(raw_base_url, repo, file) do
    case TemplateCache.get({repo, file}) do
      {:ok, form} ->
        {:ok, form}

      :miss ->
        with {:ok, yaml} <- fetch_raw(raw_base_url, repo, file),
             {:ok, form} <- parse_form(yaml, file) do
          TemplateCache.put({repo, file}, form)
          {:ok, form}
        end
    end
  end

  defp fetch_raw(raw_base_url, repo, file) do
    url = "#{raw_base_url}/#{repo}/HEAD/#{@template_dir}/#{file}"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: other}} ->
        {:error, {:unexpected_response, other}}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:network_error, inspect(reason)}}
    end
  end

  defp api_headers do
    base = [{"accept", "application/vnd.github+json"}]

    case github_token() do
      nil -> base
      token -> [{"authorization", "Bearer #{token}"} | base]
    end
  end

  # Anonymous fetches work for public repos; a token only raises rate
  # limits and unlocks private repos, so any failure here degrades to nil.
  defp github_token do
    creds = FeedbackATron.Credentials.load()

    case FeedbackATron.Credentials.get(creds, :github) do
      {:ok, %{token: token}} when is_binary(token) -> token
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # HTTPS only, except plain-HTTP loopback for Bypass in tests.
  defp validate_base_url(url) when is_binary(url) do
    if String.starts_with?(url, "https://") or
         String.starts_with?(url, "http://localhost") or
         String.starts_with?(url, "http://127.0.0.1") do
      {:ok, String.trim_trailing(url, "/")}
    else
      {:error, {:insecure_base_url, url}}
    end
  end

  defp validate_base_url(url), do: {:error, {:insecure_base_url, url}}

  defp template_file?(name) when is_binary(name) do
    Regex.match?(~r/\.ya?ml$/i, name) and
      String.downcase(name) not in ["config.yml", "config.yaml"]
  end

  defp template_file?(_), do: false

  # ---------------------------------------------------------------------------
  # Parsing
  # ---------------------------------------------------------------------------

  defp safe_yaml(yaml_string) do
    case YamlElixir.read_from_string(yaml_string) do
      {:ok, doc} ->
        {:ok, doc}

      {:error, %{__exception__: true} = error} ->
        {:error, {:yaml_error, Exception.message(error)}}

      {:error, reason} ->
        {:error, {:yaml_error, inspect(reason)}}
    end
  rescue
    error -> {:error, {:yaml_error, Exception.message(error)}}
  end

  defp build_form(doc, file) do
    fields =
      doc["body"]
      |> Enum.with_index()
      |> Enum.map(fn {block, index} -> build_field(block, index) end)

    %{
      name: doc["name"],
      file: file,
      description: string_or_nil(doc["description"]),
      labels: normalize_labels(doc["labels"]),
      title: string_or_nil(doc["title"]),
      fields: fields
    }
  end

  defp build_field(block, index) when is_map(block) do
    type = Map.get(@block_types, block["type"], :input)
    attributes = if is_map(block["attributes"]), do: block["attributes"], else: %{}
    label = if is_nil(attributes["label"]), do: "", else: to_string(attributes["label"])

    %{
      id: field_id(block, type, label, index),
      type: type,
      label: label,
      description: string_or_nil(attributes["description"]),
      placeholder: string_or_nil(attributes["placeholder"]),
      options: normalize_options(attributes["options"]),
      # Language hint for code fencing when the value is rendered
      # (GitHub issue forms: attributes.render, e.g. "shell").
      render: string_or_nil(attributes["render"]),
      # Markdown blocks are display-only and can never be required.
      required: type != :markdown and required?(block["validations"])
    }
  end

  # A non-map body block is malformed; keep a placeholder field so the
  # block count (and generated ids) stay aligned with the source file.
  defp build_field(_block, index) do
    %{
      id: "field-#{index}",
      type: :input,
      label: "",
      description: nil,
      placeholder: nil,
      options: [],
      render: nil,
      required: false
    }
  end

  defp field_id(_block, :markdown, _label, index), do: "md-#{index}"

  defp field_id(block, _type, label, index) do
    cond do
      is_binary(block["id"]) and block["id"] != "" -> block["id"]
      slugify(label) != "" -> slugify(label)
      true -> "field-#{index}"
    end
  end

  defp slugify(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp required?(%{"required" => true}), do: true
  defp required?(_), do: false

  # YAML 1.1 scalars like `true`/`false` come back as booleans (and bare
  # numbers as numbers), so every option is passed through to_string/1.
  # Checkbox options are maps of the shape %{"label" => ..., "required" => ...}.
  defp normalize_options(options) when is_list(options) do
    Enum.map(options, &stringify_option/1)
  end

  defp normalize_options(_), do: []

  defp stringify_option(%{"label" => label}), do: to_string(label)
  defp stringify_option(option) when is_map(option), do: inspect(option)
  defp stringify_option(option), do: to_string(option)

  # Form-level labels may be a YAML list or a single comma-free string.
  defp normalize_labels(labels) when is_list(labels), do: Enum.map(labels, &to_string/1)
  defp normalize_labels(labels) when is_binary(labels), do: [labels]
  defp normalize_labels(_), do: []

  defp string_or_nil(nil), do: nil
  defp string_or_nil(value) when is_binary(value), do: value
  defp string_or_nil(value), do: to_string(value)
end
