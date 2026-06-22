# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#!/usr/bin/env elixir
# Multi-repo scraper for feedback-a-tron
# Scrapes multiple GitHub repos into the Datalog fact store
#
# Usage:
#   ./scraper.exs --repos owner1/repo1,owner2/repo2
#   ./scraper.exs --file repos.txt
#   ./scraper.exs --user hyperpolymath  # All repos for user
#   ./scraper.exs --starred             # All starred repos

Mix.install([
  {:req, "~> 0.5"},
  {:jason, "~> 1.4"},
  {:optimus, "~> 0.5"}
])

defmodule Scraper do
  @moduledoc """
  Multi-repo GitHub scraper.
  
  Fetches issues from multiple repos and outputs facts
  in a format suitable for the Datalog store.
  """
  
  @github_api "https://api.github.com"

  def main(args) do
    optimus = Optimus.new!(
      name: "scraper",
      description: "Scrape GitHub repos for feedback-a-tron",
      version: "0.1.0",
      author: "feedback-a-tron",
      about: "Fetches issues from multiple GitHub repos into Datalog facts",
      allow_unknown_args: false,
      parse_double_dash: true,
      options: [
        repos: [
          short: "-r",
          long: "--repos",
          help: "Comma-separated list of repos (owner/name)",
          parser: :string
        ],
        file: [
          short: "-f",
          long: "--file",
          help: "File containing repo list (one per line)",
          parser: :string
        ],
        user: [
          short: "-u",
          long: "--user",
          help: "Fetch all repos for this user",
          parser: :string
        ],
        starred: [
          short: "-s",
          long: "--starred",
          help: "Fetch all starred repos for authenticated user",
          parser: :boolean,
          default: false
        ],
        output: [
          short: "-o",
          long: "--output",
          help: "Output file (default: stdout)",
          parser: :string
        ],
        format: [
          long: "--format",
          help: "Output format: datalog, json, csv",
          parser: :string,
          default: "datalog"
        ],
        state: [
          long: "--state",
          help: "Issue state filter: open, closed, all",
          parser: :string,
          default: "all"
        ],
        limit: [
          short: "-l",
          long: "--limit",
          help: "Max issues per repo (0 = unlimited)",
          parser: :integer,
          default: 0
        ]
      ]
    )

    case Optimus.parse!(optimus, args) do
      %{options: opts} ->
        repos = get_repos(opts)
        
        if Enum.empty?(repos) do
          IO.puts(:stderr, "No repos specified. Use --repos, --file, --user, or --starred")
          System.halt(1)
        end
        
        IO.puts(:stderr, "Scraping #{length(repos)} repos...")
        
        facts = Enum.flat_map(repos, fn repo ->
          IO.puts(:stderr, "  #{repo}...")
          scrape_repo(repo, opts)
        end)
        
        output = format_output(facts, opts.format)
        
        case opts.output do
          nil -> IO.puts(output)
          path -> File.write!(path, output)
        end
        
        IO.puts(:stderr, "Done. #{length(facts)} facts generated.")
        
      _ ->
        Optimus.parse!(optimus, ["--help"])
    end
  end

  defp get_repos(opts) do
    cond do
      opts.repos ->
        String.split(opts.repos, ",") |> Enum.map(&String.trim/1)
        
      opts.file ->
        File.read!(opts.file)
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
        
      opts.user ->
        fetch_user_repos(opts.user)
        
      opts.starred ->
        fetch_starred_repos()
        
      true ->
        []
    end
  end

  defp fetch_user_repos(username) do
    case api_get("/users/#{username}/repos", per_page: 100) do
      {:ok, repos} ->
        Enum.map(repos, & &1["full_name"])
      {:error, reason} ->
        IO.puts(:stderr, "Error fetching user repos: #{inspect(reason)}")
        []
    end
  end

  defp fetch_starred_repos do
    case api_get("/user/starred", per_page: 100) do
      {:ok, repos} ->
        Enum.map(repos, & &1["full_name"])
      {:error, reason} ->
        IO.puts(:stderr, "Error fetching starred repos: #{inspect(reason)}")
        []
    end
  end

  defp scrape_repo(repo, opts) do
    params = %{state: opts.state, per_page: 100}
    
    case api_get("/repos/#{repo}/issues", params) do
      {:ok, issues} ->
        issues = if opts.limit > 0, do: Enum.take(issues, opts.limit), else: issues
        Enum.flat_map(issues, &issue_to_facts(repo, &1))
        
      {:error, reason} ->
        IO.puts(:stderr, "    Error: #{inspect(reason)}")
        []
    end
  end

  defp issue_to_facts(repo, issue) do
    id = issue["number"]
    title = issue["title"] || ""
    body = issue["body"] || ""
    state = issue["state"] || "open"
    created_at = issue["created_at"]
    comments = issue["comments"] || 0
    author = get_in(issue, ["user", "login"])
    labels = Enum.map(issue["labels"] || [], & &1["name"])
    
    # Skip PRs (they have pull_request key)
    if issue["pull_request"] do
      []
    else
      base = [{:issue, [id, title, repo, state, created_at, comments]}]
      body_fact = [{:issue_body, [id, body]}]
      author_fact = if author, do: [{:issue_author, [id, author]}], else: []
      label_facts = Enum.map(labels, fn l -> {:issue_label, [id, l]} end)
      mention_facts = extract_mentions(id, body)
      keyword_facts = extract_keywords(id, title, body)
      
      base ++ body_fact ++ author_fact ++ label_facts ++ mention_facts ++ keyword_facts
    end
  end

  defp extract_mentions(from_id, body) do
    Regex.scan(~r/#(\d+)/, body)
    |> Enum.map(fn [_, num] -> String.to_integer(num) end)
    |> Enum.uniq()
    |> Enum.reject(& &1 == from_id)
    |> Enum.map(fn to_id -> {:mentions_issue, [from_id, to_id]} end)
  end

  defp extract_keywords(id, title, body) do
    keywords = ~w(sync reappear overwrite lost persist archive session
                  config state memory cache storage server client
                  api mcp tui vscode extension bug error crash)
    
    text = String.downcase(title <> " " <> body)
    
    keywords
    |> Enum.filter(&String.contains?(text, &1))
    |> Enum.map(fn kw -> {:issue_body_contains, [id, kw]} end)
  end

  defp format_output(facts, format) do
    case format do
      "datalog" ->
        facts
        |> Enum.map(&format_datalog_fact/1)
        |> Enum.join("\n")
        
      "json" ->
        facts
        |> Enum.map(fn {pred, args} -> %{predicate: pred, args: args} end)
        |> Jason.encode!(pretty: true)
        
      "csv" ->
        header = "predicate,arg1,arg2,arg3,arg4,arg5,arg6\n"
        rows = facts
        |> Enum.map(fn {pred, args} ->
          padded = args ++ List.duplicate("", 6 - length(args))
          [pred | padded] |> Enum.map(&csv_escape/1) |> Enum.join(",")
        end)
        |> Enum.join("\n")
        header <> rows
        
      _ ->
        "Unknown format: #{format}"
    end
  end

  defp format_datalog_fact({pred, args}) do
    args_str = args
    |> Enum.map(&format_arg/1)
    |> Enum.join(", ")
    "#{pred}(#{args_str})."
  end

  defp format_arg(arg) when is_binary(arg) do
    escaped = arg
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.slice(0, 200)  # Truncate long strings
    "\"#{escaped}\""
  end
  defp format_arg(arg) when is_atom(arg), do: Atom.to_string(arg)
  defp format_arg(arg), do: inspect(arg)

  defp csv_escape(val) when is_binary(val) do
    if String.contains?(val, [",", "\"", "\n"]) do
      "\"#{String.replace(val, "\"", "\"\"")}\""
    else
      val
    end
  end
  defp csv_escape(val), do: to_string(val)

  defp api_get(path, params \\ %{}) do
    token = System.get_env("GITHUB_TOKEN") || System.get_env("GH_TOKEN")
    
    headers = [
      {"Accept", "application/vnd.github+json"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
    headers = if token, do: [{"Authorization", "Bearer #{token}"} | headers], else: headers
    
    url = @github_api <> path
    url = if map_size(params) > 0 do
      query = Enum.map(params, fn {k, v} -> "#{k}=#{v}" end) |> Enum.join("&")
      "#{url}?#{query}"
    else
      url
    end
    
    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 401}} -> {:error, :unauthorized}
      {:ok, %{status: 403}} -> {:error, :rate_limited}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end

Scraper.main(System.argv())
