# SPDX-License-Identifier: PMPL-1.0-or-later
# Unit tests for FeedbackATron.Channel behaviour and registry.

defmodule FeedbackATron.ChannelTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Channel

  describe "registry/0" do
    test "returns a map of platform atoms to modules" do
      reg = Channel.registry()
      assert is_map(reg)
      assert map_size(reg) > 0
    end

    test "registry contains all core platforms" do
      reg = Channel.registry()
      core_platforms = [:github, :gitlab, :bitbucket, :codeberg, :bugzilla, :email]

      for platform <- core_platforms do
        assert Map.has_key?(reg, platform),
               "Registry should contain #{inspect(platform)}"
      end
    end

    test "registry contains extended platforms" do
      reg = Channel.registry()
      extended = [:nntp, :discourse, :mailman, :sourcehut, :jira, :matrix, :discord, :reddit]

      for platform <- extended do
        assert Map.has_key?(reg, platform),
               "Registry should contain #{inspect(platform)}"
      end
    end

    test "all registry values are modules" do
      reg = Channel.registry()

      for {_platform, mod} <- reg do
        assert is_atom(mod), "Registry value #{inspect(mod)} should be a module atom"
      end
    end
  end

  describe "get/1" do
    test "returns {:ok, module} for known platforms" do
      assert {:ok, FeedbackATron.Channels.GitHub} = Channel.get(:github)
      assert {:ok, FeedbackATron.Channels.GitLab} = Channel.get(:gitlab)
      assert {:ok, FeedbackATron.Channels.Bugzilla} = Channel.get(:bugzilla)
    end

    test "returns {:error, :unknown_platform} for unknown platform" do
      assert {:error, :unknown_platform} = Channel.get(:nonexistent)
      assert {:error, :unknown_platform} = Channel.get(:foobar)
    end
  end

  describe "GitHub channel behaviour" do
    test "GitHub channel implements platform/0" do
      assert :github == FeedbackATron.Channels.GitHub.platform()
    end

    test "GitHub channel implements transport/0" do
      assert :https == FeedbackATron.Channels.GitHub.transport()
    end

    test "GitHub channel validate_creds/1 requires token" do
      assert :ok = FeedbackATron.Channels.GitHub.validate_creds(%{token: "test"})
      assert {:error, _} = FeedbackATron.Channels.GitHub.validate_creds(%{})
    end
  end
end
