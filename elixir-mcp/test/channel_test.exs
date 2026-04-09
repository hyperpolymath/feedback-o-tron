# SPDX-License-Identifier: PMPL-1.0-or-later
# Tests for FeedbackATron.Channel behaviour and registry.

defmodule FeedbackATron.ChannelTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Channel

  describe "registry/0" do
    test "returns a map of platform atoms to modules" do
      registry = Channel.registry()
      assert is_map(registry)
      assert map_size(registry) > 0
    end

    test "all expected platforms are registered" do
      registry = Channel.registry()
      expected = [:github, :gitlab, :bitbucket, :codeberg, :bugzilla, :email,
                  :nntp, :discourse, :mailman, :sourcehut, :jira, :matrix,
                  :discord, :reddit]

      for platform <- expected do
        assert Map.has_key?(registry, platform),
               "Platform #{platform} not in registry"
      end
    end

    test "all registered modules implement the Channel behaviour" do
      for {platform, mod} <- Channel.registry() do
        assert Code.ensure_loaded?(mod),
               "Module #{mod} for #{platform} is not loadable"

        exports = mod.__info__(:functions)
        assert {:platform, 0} in exports, "#{mod} missing platform/0"
        assert {:transport, 0} in exports, "#{mod} missing transport/0"
        assert {:submit, 3} in exports, "#{mod} missing submit/3"
        assert {:validate_creds, 1} in exports, "#{mod} missing validate_creds/1"
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
    end
  end

  describe "platform-specific modules" do
    test "each module returns correct platform atom" do
      for {expected_platform, mod} <- Channel.registry() do
        assert mod.platform() == expected_platform,
               "#{mod}.platform() returned #{mod.platform()}, expected #{expected_platform}"
      end
    end

    test "all transports are encrypted" do
      allowed = [:https, :nntps, :smtps, :matrix]

      for {platform, mod} <- Channel.registry() do
        transport = mod.transport()
        assert transport in allowed,
               "#{platform} uses disallowed transport: #{transport}"
      end
    end
  end
end
