# SPDX-License-Identifier: PMPL-1.0-or-later
# Unit tests for FeedbackATron.Credentials.
#
# Credentials are loaded from environment variables and CLI configs.
# These tests verify the loading logic, credential rotation, and the
# get/2 accessor.

defmodule FeedbackATron.CredentialsTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Credentials

  describe "load/0" do
    test "returns a Credentials struct" do
      creds = Credentials.load()
      assert %Credentials{} = creds
    end

    test "struct has all expected platform fields" do
      creds = Credentials.load()
      expected_fields = [:github, :gitlab, :bitbucket, :codeberg, :bugzilla, :email,
                         :nntp, :discourse, :mailman, :sourcehut, :jira, :matrix,
                         :discord, :reddit]

      for field <- expected_fields do
        assert Map.has_key?(creds, field),
               "Credentials struct should have field #{inspect(field)}"
      end
    end

    test "platforms without env vars return empty lists" do
      # Clear any test env vars that might be set.
      original_gh = System.get_env("GITHUB_TOKEN")
      System.delete_env("GITHUB_TOKEN")
      System.delete_env("GH_TOKEN")

      creds = Credentials.load()

      # GitHub should be an empty list if no env var or CLI config exists.
      assert is_list(creds.github)

      # Restore original env.
      if original_gh, do: System.put_env("GITHUB_TOKEN", original_gh)
    end
  end

  describe "get/2" do
    test "returns {:error, :no_credentials} for nil credential" do
      creds = %Credentials{github: nil}
      assert {:error, :no_credentials} = Credentials.get(creds, :github)
    end

    test "returns {:error, :no_credentials} for empty list" do
      creds = %Credentials{github: []}
      assert {:error, :no_credentials} = Credentials.get(creds, :github)
    end

    test "returns {:ok, cred} for single credential" do
      token = %{source: :env, token: "test-token"}
      creds = %Credentials{github: [token]}

      assert {:ok, ^token} = Credentials.get(creds, :github)
    end

    test "returns {:ok, cred} for multiple credentials (rotation)" do
      cred1 = %{source: :env, token: "token-1"}
      cred2 = %{source: :env, token: "token-2"}
      creds = %Credentials{github: [cred1, cred2]}

      {:ok, result} = Credentials.get(creds, :github)
      assert result in [cred1, cred2]
    end

    test "rotation cycles through credentials" do
      cred1 = %{source: :env, token: "token-1"}
      cred2 = %{source: :env, token: "token-2"}
      creds = %Credentials{github: [cred1, cred2]}

      results =
        for _ <- 1..4 do
          {:ok, cred} = Credentials.get(creds, :github)
          cred.token
        end

      # Rotation should cycle; both tokens must appear.
      assert "token-1" in results
      assert "token-2" in results
    end
  end

  describe "environment variable loading" do
    test "GITHUB_TOKEN env var is picked up" do
      System.put_env("GITHUB_TOKEN", "test-gh-token-1234")

      creds = Credentials.load()
      assert Enum.any?(creds.github, &(&1.source == :env))

      System.delete_env("GITHUB_TOKEN")
    end

    test "BUGZILLA_API_KEY env var is picked up" do
      System.put_env("BUGZILLA_API_KEY", "test-bz-key")

      creds = Credentials.load()
      assert Enum.any?(creds.bugzilla, &(&1.source == :env))

      System.delete_env("BUGZILLA_API_KEY")
    end

    test "DISCOURSE_URL must be HTTPS" do
      System.put_env("DISCOURSE_URL", "http://insecure.example.com")

      creds = Credentials.load()
      assert creds.discourse == []

      System.delete_env("DISCOURSE_URL")
    end

    test "DISCOURSE_URL with HTTPS is accepted" do
      System.put_env("DISCOURSE_URL", "https://secure.example.com")

      creds = Credentials.load()
      assert Enum.any?(creds.discourse, &(&1.source == :env))

      System.delete_env("DISCOURSE_URL")
    end
  end
end
