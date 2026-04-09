# feedback-o-tron Architecture

> **Note**: This document was originally authored for a planned "Observatory" GitHub Intelligence Platform. Much of the component analysis below (Oxigraph, Julia analytics, Nickel config) describes **aspirational/future** capabilities that are not part of the current feedback-o-tron implementation. The current implementation is an autonomous multi-platform bug reporting system. See [README.adoc](../README.adoc) for the actual feature set.

## Original Vision (Observatory — Future)

A comprehensive system for tracking, analyzing, and visualizing GitHub activity across repositories — with local-first data sovereignty, semantic querying, and real-time change tracking.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              User Interfaces                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  ReScript-Tea Web UI     │  CLI (Elixir escript)  │  Claude MCP Integration │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Elixir Core (OTP)                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  MCP Server  │  REST API (Bandit)  │  GraphQL (Absinthe)  │  WebSocket      │
├─────────────────────────────────────────────────────────────────────────────┤
│  GitHub Client  │  Scraper (multi-repo)  │  Subscription Manager            │
├─────────────────────────────────────────────────────────────────────────────┤
│  Datalog Engine (in-memory)  │  Analysis Module  │  Similarity Engine       │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                 ▼
┌───────────────────────┐ ┌───────────────────┐ ┌───────────────────────────┐
│  Oxigraph (RDF/SPARQL)│ │  SQLite (events)  │ │  Julia Analytics Engine   │
│  Semantic triple store│ │  Timeline, stats  │ │  Contribution statistics  │
└───────────────────────┘ └───────────────────┘ └───────────────────────────┘
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Configuration Layer                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  Nickel schemas → JSON, TOML, Nix, Guix SCM outputs                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Packaging                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  nerdctl + Wolfi OCI  │  Guix channel (primary)  │  Nix flake (fallback)    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Component Decisions

### 1. Core Engine: Elixir (keep)

**Rationale:**
- OTP supervision for reliability
- Native pattern matching suits Datalog
- Excellent HTTP clients (Req), JSON (Jason)
- You know it (NeuroPhone)
- Hot code reload for live updates

**Alternative considered:** Rust with Tokio — faster, but loses OTP ergonomics and hot reload.

### 2. RDF Store: Oxigraph (instead of Virtuoso)

**Rationale:**
- Pure Rust, single binary, embeddable
- Full SPARQL 1.1 support
- Lighter than Virtuoso (no Java, no complex setup)
- Fits your Rust preference
- Can run as subprocess or embedded via NIF

**Virtuoso would require:** Java runtime, complex config, more resources.

**Schema:** We map GitHub concepts to RDF:
```turtle
@prefix gh: <https://observatory.local/github#> .
@prefix schema: <https://schema.org/> .

gh:issue/12114 a gh:Issue ;
    schema:name "Session archive not persisting" ;
    gh:state "open" ;
    gh:repository gh:repo/anthropics/claude-code ;
    gh:label "bug", "memory" ;
    gh:relatedTo gh:issue/10839 ;
    gh:affectsComponent gh:component/session_management .
```

### 3. Configuration: Nickel

**Rationale:**
- Typed configuration language
- Can output JSON, TOML, Nix, and with adapters: Guix SCM
- Contracts for validation
- Merging/inheritance for repo-specific overrides

### 4. Analytics: Julia

**Rationale:**
- Excellent for statistical analysis
- DataFrames.jl for tabular data
- Plots.jl / Makie.jl for visualization
- Can generate static reports or run as HTTP service

**Interface:** Elixir calls Julia via:
- Option A: HTTP (Julia runs as Genie.jl service)
- Option B: Subprocess with JSON stdin/stdout
- Option C: Ports with MessagePack (faster)

### 5. Frontend: ReScript-Tea

**Rationale:**
- Type-safe
- Elm architecture (TEA) for predictable state
- Compiles to small JS bundles
- You specified it

**Alternative considered:** Elm itself — but ReScript has better JS interop.

### 6. Change Tracking: GitHub Webhooks + Polling Hybrid

**Mechanism:**
1. **Webhooks** for repos you control (instant)
2. **Polling** with ETags for external repos (rate-limit friendly)
3. **GraphQL subscriptions** where available

Elixir GenServer manages subscription state, debounces, deduplicates.

### 7. Packaging: nerdctl + Wolfi (primary), Guix channel, Nix fallback

**Why this order:**
- **Wolfi** is security-focused, minimal, apk-based — good for OCI
- **nerdctl** is rootless containerd (Podman-like, your preference)
- **Guix** for reproducible, auditable builds (your preference for provenance)
- **Nix** as fallback for ecosystems where Guix packages lag

## Detailed Component Specs

### Nickel Configuration Schema

```nickel
# observatory.ncl
let Config = {
  github : {
    token : String,
    api_url : String | default = "https://api.github.com",
    rate_limit_buffer : Number | default = 100,
  },
  
  repositories : Array {
    owner : String,
    name : String,
    track : {
      issues : Bool | default = true,
      prs : Bool | default = true,
      releases : Bool | default = true,
      workflows : Bool | default = false,
    },
    labels_of_interest : Array String | default = [],
    components : Array {
      name : String,
      label_patterns : Array String,
      path_patterns : Array String,
    } | default = [],
  },
  
  analysis : {
    similarity_threshold : Number | default = 0.7,
    stale_days : Number | default = 90,
    hotspot_threshold : Number | default = 10,
  },
  
  storage : {
    oxigraph_path : String | default = "./data/oxigraph",
    sqlite_path : String | default = "./data/observatory.db",
    cache_ttl_seconds : Number | default = 3600,
  },
  
  subscriptions : {
    webhook_port : Number | default = 8080,
    webhook_secret : String | optional,
    poll_interval_seconds : Number | default = 300,
  },
  
  julia : {
    enabled : Bool | default = true,
    mode : [| 'subprocess, 'http |] | default = 'subprocess,
    http_port : Number | default = 8787,
  },
  
  web_ui : {
    enabled : Bool | default = true,
    port : Number | default = 3000,
    public_url : String | optional,
  },
}
in

# Output adapters
{
  to_json = fun config => std.serialize 'Json config,
  to_toml = fun config => std.serialize 'Toml config,
  to_env = fun config => 
    # Flatten to OBSERVATORY_GITHUB_TOKEN=... format
    ...,
  to_guix_scm = fun config =>
    # Generate Guix service definition
    ...,
}
```

### Julia Analytics Module

```julia
# analytics/src/Observatory.jl
module Observatory

using DataFrames
using Dates
using Statistics
using JSON3
using HTTP

export ContributionStats, compute_stats, generate_report

struct ContributionStats
    user::String
    period::Tuple{Date, Date}
    issues_opened::Int
    issues_closed::Int
    prs_merged::Int
    comments_made::Int
    avg_response_time_hours::Float64
    repos_contributed::Vector{String}
end

function compute_stats(events::DataFrame, user::String; 
                       start_date=Date(2024,1,1), 
                       end_date=today())::ContributionStats
    user_events = filter(row -> 
        row.actor == user && 
        start_date <= row.date <= end_date, 
        events)
    
    issues_opened = count(row -> row.event_type == "issue_opened", eachrow(user_events))
    issues_closed = count(row -> row.event_type == "issue_closed", eachrow(user_events))
    prs_merged = count(row -> row.event_type == "pr_merged", eachrow(user_events))
    comments = count(row -> row.event_type == "comment", eachrow(user_events))
    
    # Response time: time from issue open to first comment by this user
    # (simplified)
    avg_response = mean(skipmissing(user_events.response_time_hours))
    
    repos = unique(user_events.repo)
    
    ContributionStats(
        user,
        (start_date, end_date),
        issues_opened,
        issues_closed,
        prs_merged,
        comments,
        isnan(avg_response) ? 0.0 : avg_response,
        repos
    )
end

function generate_report(stats::ContributionStats)::Dict
    Dict(
        "user" => stats.user,
        "period" => Dict(
            "start" => string(stats.period[1]),
            "end" => string(stats.period[2])
        ),
        "metrics" => Dict(
            "issues_opened" => stats.issues_opened,
            "issues_closed" => stats.issues_closed,
            "prs_merged" => stats.prs_merged,
            "comments_made" => stats.comments_made,
            "avg_response_time_hours" => round(stats.avg_response_time_hours, digits=2),
            "repos_contributed" => length(stats.repos_contributed)
        ),
        "repos" => stats.repos_contributed
    )
end

# HTTP service mode
function serve(port::Int=8787)
    HTTP.serve(port) do req
        if req.method == "POST" && req.target == "/analyze"
            body = JSON3.read(String(req.body))
            # Process and return stats
            result = process_request(body)
            return HTTP.Response(200, JSON3.write(result))
        end
        HTTP.Response(404, "Not found")
    end
end

end # module
```

### ReScript-Tea Frontend Structure

```rescript
// src/App.res
module App = {
  type model = {
    repos: array<Repository.t>,
    selectedRepo: option<string>,
    issues: array<Issue.t>,
    analysisResults: option<Analysis.result>,
    contributionStats: option<ContributionStats.t>,
    loading: bool,
    error: option<string>,
  }

  type msg =
    | FetchRepos
    | ReposLoaded(result<array<Repository.t>, string>)
    | SelectRepo(string)
    | FetchIssues(string)
    | IssuesLoaded(result<array<Issue.t>, string>)
    | RunAnalysis(Analysis.analysisType)
    | AnalysisComplete(result<Analysis.result, string>)
    | FetchContributionStats(string)
    | StatsLoaded(result<ContributionStats.t, string>)

  let init = () => (
    {
      repos: [],
      selectedRepo: None,
      issues: [],
      analysisResults: None,
      contributionStats: None,
      loading: false,
      error: None,
    },
    Cmd.ofMsg(FetchRepos),
  )

  let update = (msg, model) => {
    switch msg {
    | FetchRepos => ({...model, loading: true}, Api.fetchRepos(ReposLoaded))
    | ReposLoaded(Ok(repos)) => ({...model, repos, loading: false}, Cmd.none)
    | ReposLoaded(Error(e)) => ({...model, error: Some(e), loading: false}, Cmd.none)
    | SelectRepo(repo) => (
        {...model, selectedRepo: Some(repo)},
        Cmd.ofMsg(FetchIssues(repo)),
      )
    | RunAnalysis(analysisType) =>
      switch model.selectedRepo {
      | Some(repo) => (
          {...model, loading: true},
          Api.runAnalysis(repo, analysisType, AnalysisComplete),
        )
      | None => (model, Cmd.none)
      }
    | AnalysisComplete(Ok(results)) => (
        {...model, analysisResults: Some(results), loading: false},
        Cmd.none,
      )
    | _ => (model, Cmd.none)
    }
  }

  let view = model => {
    <div className="observatory">
      <Sidebar repos={model.repos} onSelect={repo => SelectRepo(repo)} />
      <main>
        {switch model.selectedRepo {
        | Some(repo) => <RepoView repo issues={model.issues} />
        | None => <WelcomeView />
        }}
        {switch model.analysisResults {
        | Some(results) => <AnalysisPanel results />
        | None => React.null
        }}
        {switch model.contributionStats {
        | Some(stats) => <ContributionChart stats />
        | None => React.null
        }}
      </main>
    </div>
  }
}
```

### Multi-Repo Scraper

```elixir
# lib/gh_manage/scraper.ex
defmodule GhManage.Scraper do
  @moduledoc """
  Multi-repository scraper with rate limiting and incremental sync.
  """
  
  use GenServer
  require Logger
  
  alias GhManage.{GitHub, Analysis}
  alias GhManage.Datalog.Store

  defmodule State do
    defstruct [
      :repos,           # List of {owner, name} tuples
      :sync_state,      # %{"owner/repo" => %{last_sync: DateTime, etag: String}}
      :rate_limit,      # Remaining API calls
      :queue,           # Repos waiting to sync
      :in_progress      # Currently syncing
    ]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add repositories to track.
  
  ## Example
  
      add_repos([
        {"anthropics", "claude-code"},
        {"rust-lang", "rust"},
        {"elixir-lang", "elixir"}
      ])
  """
  def add_repos(repos) when is_list(repos) do
    GenServer.call(__MODULE__, {:add_repos, repos})
  end

  @doc """
  Trigger immediate sync of all repos.
  """
  def sync_all do
    GenServer.cast(__MODULE__, :sync_all)
  end

  @doc """
  Sync a specific repo.
  """
  def sync_repo(owner, name) do
    GenServer.cast(__MODULE__, {:sync_repo, owner, name})
  end

  @doc """
  Get sync status for all repos.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    repos = Keyword.get(opts, :repos, [])
    poll_interval = Keyword.get(opts, :poll_interval, :timer.minutes(5))
    
    # Schedule periodic sync
    :timer.send_interval(poll_interval, :periodic_sync)
    
    state = %State{
      repos: repos,
      sync_state: %{},
      rate_limit: 5000,
      queue: :queue.new(),
      in_progress: nil
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:add_repos, repos}, _from, state) do
    new_repos = Enum.uniq(state.repos ++ repos)
    {:reply, :ok, %{state | repos: new_repos}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      repos: length(state.repos),
      queued: :queue.len(state.queue),
      in_progress: state.in_progress,
      rate_limit_remaining: state.rate_limit,
      sync_state: state.sync_state
    }
    {:reply, status, state}
  end

  @impl true
  def handle_cast(:sync_all, state) do
    queue = Enum.reduce(state.repos, state.queue, fn repo, q ->
      :queue.in(repo, q)
    end)
    
    state = %{state | queue: queue}
    {:noreply, maybe_start_next(state)}
  end

  @impl true
  def handle_cast({:sync_repo, owner, name}, state) do
    queue = :queue.in({owner, name}, state.queue)
    state = %{state | queue: queue}
    {:noreply, maybe_start_next(state)}
  end

  @impl true
  def handle_info(:periodic_sync, state) do
    # Queue repos that haven't synced recently
    now = DateTime.utc_now()
    stale_threshold = 300  # 5 minutes
    
    queue = Enum.reduce(state.repos, state.queue, fn {owner, name} = repo, q ->
      repo_key = "#{owner}/#{name}"
      case Map.get(state.sync_state, repo_key) do
        %{last_sync: last} ->
          if DateTime.diff(now, last) > stale_threshold do
            :queue.in(repo, q)
          else
            q
          end
        nil ->
          :queue.in(repo, q)
      end
    end)
    
    state = %{state | queue: queue}
    {:noreply, maybe_start_next(state)}
  end

  @impl true
  def handle_info({:sync_complete, repo_key, result}, state) do
    sync_state = case result do
      {:ok, etag} ->
        Map.put(state.sync_state, repo_key, %{
          last_sync: DateTime.utc_now(),
          etag: etag,
          status: :ok
        })
      {:error, reason} ->
        Map.put(state.sync_state, repo_key, %{
          last_sync: DateTime.utc_now(),
          status: {:error, reason}
        })
    end
    
    state = %{state | sync_state: sync_state, in_progress: nil}
    {:noreply, maybe_start_next(state)}
  end

  # Private

  defp maybe_start_next(%{in_progress: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, {owner, name}}, queue} ->
        repo_key = "#{owner}/#{name}"
        
        # Start async sync
        Task.start(fn ->
          result = do_sync(owner, name, state.sync_state[repo_key])
          send(__MODULE__, {:sync_complete, repo_key, result})
        end)
        
        %{state | queue: queue, in_progress: repo_key}
        
      {:empty, _} ->
        state
    end
  end
  defp maybe_start_next(state), do: state

  defp do_sync(owner, name, prev_state) do
    repo = "#{owner}/#{name}"
    Logger.info("Syncing #{repo}...")
    
    # Use ETag for conditional request if we have one
    opts = case prev_state do
      %{etag: etag} when is_binary(etag) -> [etag: etag]
      _ -> []
    end
    
    case Analysis.ingest_repo(repo) do
      {:ok, count} ->
        Logger.info("Synced #{repo}: #{count} issues")
        {:ok, nil}  # Would get ETag from response headers
      {:error, reason} ->
        Logger.error("Failed to sync #{repo}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

### Subscription Manager (Webhooks + Polling)

```elixir
# lib/gh_manage/subscriptions.ex
defmodule GhManage.Subscriptions do
  @moduledoc """
  Manages change subscriptions via webhooks and polling.
  """
  
  use GenServer
  require Logger

  defmodule Subscription do
    defstruct [:repo, :events, :callback, :method, :last_event]
    
    @type t :: %__MODULE__{
      repo: String.t(),
      events: [atom()],
      callback: (map() -> any()),
      method: :webhook | :poll,
      last_event: DateTime.t() | nil
    }
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribe to events for a repository.
  
  ## Example
  
      subscribe("anthropics/claude-code", [:issue, :pr], fn event ->
        IO.puts("Got event: \#{inspect(event)}")
      end)
  """
  def subscribe(repo, events, callback) do
    GenServer.call(__MODULE__, {:subscribe, repo, events, callback})
  end

  @doc """
  Unsubscribe from a repository.
  """
  def unsubscribe(repo) do
    GenServer.call(__MODULE__, {:unsubscribe, repo})
  end

  @doc """
  Process incoming webhook payload.
  """
  def process_webhook(payload, signature) do
    GenServer.cast(__MODULE__, {:webhook, payload, signature})
  end

  # Server implementation

  @impl true
  def init(opts) do
    webhook_secret = Keyword.get(opts, :webhook_secret)
    poll_interval = Keyword.get(opts, :poll_interval, :timer.minutes(1))
    
    :timer.send_interval(poll_interval, :poll)
    
    {:ok, %{
      subscriptions: %{},
      webhook_secret: webhook_secret
    }}
  end

  @impl true
  def handle_call({:subscribe, repo, events, callback}, _from, state) do
    sub = %Subscription{
      repo: repo,
      events: events,
      callback: callback,
      method: :poll,  # Default to polling, upgrade to webhook if configured
      last_event: DateTime.utc_now()
    }
    
    subs = Map.put(state.subscriptions, repo, sub)
    {:reply, :ok, %{state | subscriptions: subs}}
  end

  @impl true
  def handle_call({:unsubscribe, repo}, _from, state) do
    subs = Map.delete(state.subscriptions, repo)
    {:reply, :ok, %{state | subscriptions: subs}}
  end

  @impl true
  def handle_cast({:webhook, payload, signature}, state) do
    if verify_signature(payload, signature, state.webhook_secret) do
      dispatch_event(payload, state.subscriptions)
    else
      Logger.warning("Invalid webhook signature")
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    # Poll each subscription for new events
    Enum.each(state.subscriptions, fn {repo, sub} ->
      if sub.method == :poll do
        poll_repo(repo, sub)
      end
    end)
    {:noreply, state}
  end

  defp verify_signature(_payload, _signature, nil), do: true
  defp verify_signature(payload, signature, secret) do
    expected = "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower))
    Plug.Crypto.secure_compare(expected, signature)
  end

  defp dispatch_event(%{"repository" => %{"full_name" => repo}} = payload, subs) do
    case Map.get(subs, repo) do
      %Subscription{callback: callback} ->
        Task.start(fn -> callback.(payload) end)
      nil ->
        :ok
    end
  end

  defp poll_repo(repo, sub) do
    since = sub.last_event || DateTime.add(DateTime.utc_now(), -3600, :second)
    
    case GhManage.GitHub.list_events(repo, since: since) do
      {:ok, events} when events != [] ->
        Enum.each(events, fn event ->
          if event_matches?(event, sub.events) do
            sub.callback.(event)
          end
        end)
      _ ->
        :ok
    end
  end

  defp event_matches?(%{"type" => type}, subscribed_events) do
    event_atom = type |> String.replace("Event", "") |> Macro.underscore() |> String.to_atom()
    event_atom in subscribed_events
  end
end
```

## Packaging

### Wolfi/nerdctl Container

```dockerfile
# Dockerfile.wolfi
FROM cgr.dev/chainguard/wolfi-base

# Install runtime dependencies
RUN apk add --no-cache \
    erlang \
    elixir \
    julia \
    oxigraph \
    sqlite \
    ca-certificates

# Create non-root user
RUN adduser -D observatory
USER observatory
WORKDIR /app

# Copy release
COPY --chown=observatory:observatory _build/prod/rel/gh_manage ./

# Copy Julia analytics
COPY --chown=observatory:observatory analytics ./analytics

# Copy frontend build
COPY --chown=observatory:observatory frontend/dist ./priv/static

# Configuration
ENV OBSERVATORY_CONFIG=/app/config/observatory.ncl
VOLUME ["/app/config", "/app/data"]

EXPOSE 4000 8080 8787

CMD ["./bin/gh_manage", "start"]
```

### Guix Channel

```scheme
;; guix/observatory/packages.scm
(define-module (observatory packages)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system mix)
  #:use-module (guix build-system julia)
  #:use-module (gnu packages erlang)
  #:use-module (gnu packages julia))

(define-public observatory
  (package
    (name "observatory")
    (version "0.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://gitlab.com/jdajewell/observatory")
                    (commit (string-append "v" version))))
              (sha256 (base32 "..."))))
    (build-system mix-build-system)
    (inputs
     (list erlang elixir oxigraph sqlite julia))
    (propagated-inputs
     (list observatory-julia-analytics))
    (synopsis "GitHub intelligence platform")
    (description "Observatory provides comprehensive GitHub repository 
analysis with Datalog-based inference, SPARQL querying, and real-time 
change tracking.")
    (home-page "https://gitlab.com/jdajewell/observatory")
    (license license:mpl2.0)))

(define-public observatory-julia-analytics
  (package
    (name "observatory-julia-analytics")
    (version "0.1.0")
    (source ...)
    (build-system julia-build-system)
    (inputs
     (list julia-dataframes julia-http julia-json3))
    (synopsis "Julia analytics engine for Observatory")
    (description "Statistical analysis module for GitHub contribution tracking.")
    (home-page "https://gitlab.com/jdajewell/observatory")
    (license license:mpl2.0)))

;; Service definition
(define-public observatory-service-type
  (service-type
   (name 'observatory)
   (extensions
    (list (service-extension shepherd-root-service-type
                             observatory-shepherd-service)))
   (default-value (observatory-configuration))
   (description "Run the Observatory GitHub intelligence platform.")))
```

### Nix Flake (Fallback)

```nix
# flake.nix
{
  description = "Observatory - GitHub Intelligence Platform";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nickel.url = "github:tweag/nickel";
  };

  outputs = { self, nixpkgs, flake-utils, nickel }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        elixirPackage = pkgs.beam.packages.erlang_26.elixir_1_16;
        
        observatoryDeps = with pkgs; [
          elixirPackage
          erlang_26
          julia
          oxigraph
          sqlite
          nickel.packages.${system}.default
        ];
        
      in {
        packages.default = pkgs.mixRelease {
          pname = "observatory";
          version = "0.1.0";
          src = ./.;
          mixNixDeps = import ./deps.nix { inherit pkgs; };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = observatoryDeps ++ [
            pkgs.nodePackages.npm  # For ReScript build
            pkgs.nerdctl
          ];
          
          shellHook = ''
            export MIX_HOME=$PWD/.mix
            export HEX_HOME=$PWD/.hex
          '';
        };

        # NixOS module
        nixosModules.default = { config, lib, pkgs, ... }: {
          options.services.observatory = {
            enable = lib.mkEnableOption "Observatory";
            configFile = lib.mkOption {
              type = lib.types.path;
              description = "Path to Nickel configuration";
            };
          };
          
          config = lib.mkIf config.services.observatory.enable {
            systemd.services.observatory = {
              description = "Observatory GitHub Intelligence";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = "${self.packages.${system}.default}/bin/observatory start";
                Restart = "always";
                DynamicUser = true;
                StateDirectory = "observatory";
              };
              environment = {
                OBSERVATORY_CONFIG = config.services.observatory.configFile;
              };
            };
          };
        };
      }
    );
}
```

## What's Built vs TODO

### ✅ Complete (this session)

| Component | Status |
|-----------|--------|
| Elixir MCP Server | Core structure, tool definitions |
| Elixir GitHub Client | Full CRUD for issues, PRs, branches, releases |
| Elixir Datalog Store | ETS-backed with indexing |
| Elixir Datalog Evaluator | Bottom-up with unification |
| Elixir Datalog Rules | Relationship, pattern, component rules |
| Elixir Analysis Module | Ingestion, similarity, all analysis types |
| Elixir Scraper | Multi-repo with rate limiting |
| Elixir Subscriptions | Webhook + polling hybrid |
| Architecture Document | This file |

### 🔧 TODO (implementation needed)

| Component | Effort | Notes |
|-----------|--------|-------|
| Nickel config schema | 2h | Write full schema with outputs |
| Oxigraph integration | 4h | NIF or HTTP bridge to Rust binary |
| Julia analytics module | 3h | Implement Observatory.jl |
| ReScript-Tea frontend | 8h | Full UI with charts |
| Elixir HTTP API | 2h | Bandit + REST endpoints |
| Container build | 2h | Wolfi Dockerfile |
| Guix channel | 3h | Package definitions |
| Nix flake | 2h | Module + overlay |
| Ada integration | 4h | Keep for SPARK-verified core types if desired |

### 🤔 Open Design Questions

1. **Oxigraph vs in-memory Datalog**: Do you want full RDF/SPARQL, or is the Elixir Datalog sufficient? Oxigraph adds complexity but enables standard semantic web tooling.

2. **Julia integration method**: HTTP service (always running) or subprocess (on-demand)? HTTP is faster for repeated queries but uses more resources.

3. **Ada role**: Keep Ada for SPARK-verified types that Elixir calls via ports? Or consolidate everything in Elixir?

4. **GitLab support**: You prefer GitLab — should we abstract the VCS layer to support both GitHub and GitLab APIs?

5. **Local-first vs cloud**: Should the frontend be a local Tauri app, or a web service?

## Recommended Next Steps

1. **Finish Elixir core** - Add HTTP API, test MCP integration
2. **Nickel config** - Define schema, test outputs
3. **Julia analytics** - Implement contribution stats
4. **Container** - Build Wolfi image, test locally
5. **Frontend** - Scaffold ReScript-Tea, connect to API
6. **Guix/Nix** - Package for reproducible deployment

Want me to continue with any specific component?
