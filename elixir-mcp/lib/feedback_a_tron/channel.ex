# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Channel do
  @moduledoc """
  Behaviour for feedback submission channels.

  Every channel must implement:
  - `platform/0` — atom identifying the platform
  - `submit/3` — submit an issue given credentials and options
  - `validate_creds/1` — check that credentials are usable
  - `transport/0` — the secure transport type (:https, :nntps, :smtps, :matrix)

  All channels MUST use encrypted transport. No plaintext ever.
  DNS resolution uses DoH/DoT/DoQ exclusively (see SecureDNS).
  """

  @type issue :: %{
          title: String.t(),
          body: String.t(),
          repo: String.t() | nil
        }

  @type cred :: map()
  @type opts :: keyword()
  @type submit_result ::
          {:ok, %{platform: atom(), url: String.t()}}
          | {:error, %{platform: atom(), error: term()}}

  @doc "Atom identifying this channel (e.g. :nntp, :discourse, :matrix)."
  @callback platform() :: atom()

  @doc "Secure transport type — must be encrypted."
  @callback transport() :: :https | :nntps | :smtps | :matrix

  @doc "Submit an issue/report to this channel."
  @callback submit(issue(), cred(), opts()) :: submit_result()

  @doc "Validate that credentials are sufficient for submission."
  @callback validate_creds(cred()) :: :ok | {:error, String.t()}

  @doc """
  Returns all registered channel modules, keyed by platform atom.
  """
  def registry do
    %{
      # Original channels (legacy dispatch, will be migrated)
      github: FeedbackATron.Channels.GitHub,
      gitlab: FeedbackATron.Channels.GitLab,
      bitbucket: FeedbackATron.Channels.Bitbucket,
      codeberg: FeedbackATron.Channels.Codeberg,
      bugzilla: FeedbackATron.Channels.Bugzilla,
      email: FeedbackATron.Channels.Email,
      # New secure channels
      nntp: FeedbackATron.Channels.NNTP,
      discourse: FeedbackATron.Channels.Discourse,
      mailman: FeedbackATron.Channels.Mailman,
      sourcehut: FeedbackATron.Channels.SourceHut,
      jira: FeedbackATron.Channels.Jira,
      matrix: FeedbackATron.Channels.Matrix,
      discord: FeedbackATron.Channels.Discord,
      reddit: FeedbackATron.Channels.Reddit
    }
  end

  @doc "Look up a channel module by platform atom."
  def get(platform) do
    case Map.get(registry(), platform) do
      nil -> {:error, :unknown_platform}
      mod -> {:ok, mod}
    end
  end
end
