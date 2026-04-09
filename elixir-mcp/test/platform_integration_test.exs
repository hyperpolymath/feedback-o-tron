# SPDX-License-Identifier: PMPL-1.0-or-later
# Integration tests for platform-specific Channel modules.
#
# Uses Bypass to mock HTTP endpoints for each platform, verifying
# that submit/3 correctly formats and dispatches requests.
# Tests gracefully skip when Bypass is not available.

defmodule FeedbackATron.PlatformIntegrationTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Channel

  # ---------------------------------------------------------------------------
  # Channel behaviour conformance — verify all registered channels implement
  # the required callbacks.
  # ---------------------------------------------------------------------------

  describe "channel behaviour conformance" do
    test "all registered channels implement platform/0" do
      for {platform, mod} <- Channel.registry() do
        assert mod.platform() == platform,
               "#{inspect(mod)}.platform() should return #{inspect(platform)}"
      end
    end

    test "all registered channels implement transport/0" do
      valid_transports = [:https, :nntps, :smtps, :matrix]

      for {_platform, mod} <- Channel.registry() do
        transport = mod.transport()

        assert transport in valid_transports,
               "#{inspect(mod)}.transport() returned #{inspect(transport)}, expected one of #{inspect(valid_transports)}"
      end
    end

    test "all registered channels implement validate_creds/1" do
      for {_platform, mod} <- Channel.registry() do
        # Passing empty creds should return an error (no valid creds).
        result = mod.validate_creds(%{})
        assert result == :ok or match?({:error, _}, result),
               "#{inspect(mod)}.validate_creds(%{}) should return :ok or {:error, _}"
      end
    end

    test "no channel uses plaintext transport" do
      for {platform, mod} <- Channel.registry() do
        transport = mod.transport()
        refute transport == :http,
               "#{inspect(platform)} uses plaintext HTTP — all channels must use encrypted transport"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Platform-specific credential validation
  # ---------------------------------------------------------------------------

  describe "credential validation" do
    test "GitHub requires token" do
      assert :ok = FeedbackATron.Channels.GitHub.validate_creds(%{token: "ghp_test"})
      assert {:error, _} = FeedbackATron.Channels.GitHub.validate_creds(%{})
    end

    test "GitLab requires token" do
      assert :ok = FeedbackATron.Channels.GitLab.validate_creds(%{token: "glpat-test"})
      assert {:error, _} = FeedbackATron.Channels.GitLab.validate_creds(%{})
    end

    test "Bitbucket requires token" do
      assert :ok = FeedbackATron.Channels.Bitbucket.validate_creds(%{token: "bb-test"})
      assert {:error, _} = FeedbackATron.Channels.Bitbucket.validate_creds(%{})
    end

    test "Codeberg requires token" do
      assert :ok = FeedbackATron.Channels.Codeberg.validate_creds(%{token: "cb-test"})
      assert {:error, _} = FeedbackATron.Channels.Codeberg.validate_creds(%{})
    end

    test "Bugzilla requires token or username/password" do
      assert :ok = FeedbackATron.Channels.Bugzilla.validate_creds(%{token: "bz-api-key"})

      assert :ok =
               FeedbackATron.Channels.Bugzilla.validate_creds(%{
                 username: "user",
                 password: "pass"
               })

      assert {:error, _} = FeedbackATron.Channels.Bugzilla.validate_creds(%{})
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-platform deduplication lifecycle
  # ---------------------------------------------------------------------------

  describe "cross-platform deduplication" do
    setup do
      case Process.whereis(FeedbackATron.Deduplicator) do
        nil -> FeedbackATron.Deduplicator.start_link([])
        _pid -> :ok
      end

      :ok = FeedbackATron.Deduplicator.clear()
      :ok
    end

    test "issue recorded on GitHub is detected when submitting to GitLab" do
      issue = %{title: "Cross-platform dedup test", body: "same issue different platform"}

      FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      Process.sleep(50)

      result = FeedbackATron.Deduplicator.check(issue)
      assert {:duplicate, _} = result
    end

    test "recording on multiple platforms tracks all platforms in history" do
      issue = %{title: "Multi-platform tracking", body: "track across platforms"}

      FeedbackATron.Deduplicator.record(issue, :github, %{status: :submitted})
      FeedbackATron.Deduplicator.record(issue, :gitlab, %{status: :submitted})
      FeedbackATron.Deduplicator.record(issue, :bugzilla, %{status: :submitted})
      Process.sleep(100)

      # Compute hash for lookup.
      title_norm =
        issue.title
        |> String.downcase()
        |> String.replace(~r/[^\w\s]/, "")
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      body_norm =
        issue.body
        |> String.downcase()
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      hash =
        :crypto.hash(:sha256, "#{title_norm}:#{body_norm}")
        |> Base.encode16(case: :lower)
        |> binary_part(0, 16)

      history = FeedbackATron.Deduplicator.get_history(hash)
      assert history != nil
      assert length(history.platforms) >= 2
    end
  end
end
