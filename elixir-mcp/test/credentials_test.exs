# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# Unit tests for FeedbackATron.Credentials.

defmodule FeedbackATron.CredentialsTest do
  use ExUnit.Case, async: true

  alias FeedbackATron.Credentials

  describe "load/0" do
    test "returns a Credentials struct" do
      creds = Credentials.load()
      assert %Credentials{} = creds
    end

    test "struct has all platform fields" do
      creds = Credentials.load()

      fields = [
        :github,
        :gitlab,
        :bitbucket,
        :codeberg,
        :bugzilla,
        :email,
        :nntp,
        :discourse,
        :mailman,
        :sourcehut,
        :jira,
        :matrix,
        :discord,
        :reddit
      ]

      for field <- fields do
        assert Map.has_key?(creds, field),
               "Missing field: #{field}"
      end
    end

    test "platforms without env vars return empty lists or nil" do
      # In test env, we expect no credentials set
      creds = Credentials.load()
      # GitHub returns a list (possibly empty)
      assert is_list(creds.github)
    end
  end

  describe "get/2" do
    test "returns {:error, :no_credentials} for nil" do
      creds = %Credentials{github: nil}
      assert {:error, :no_credentials} = Credentials.get(creds, :github)
    end

    test "returns {:error, :no_credentials} for empty list" do
      creds = %Credentials{github: []}
      assert {:error, :no_credentials} = Credentials.get(creds, :github)
    end

    test "returns {:ok, cred} for single credential" do
      cred = %{source: :env, token: "test-token"}
      creds = %Credentials{github: [cred]}
      assert {:ok, ^cred} = Credentials.get(creds, :github)
    end

    test "returns a credential from list with multiple entries (rotation)" do
      cred1 = %{source: :env, token: "token-1"}
      cred2 = %{source: :cli, token: "token-2"}
      creds = %Credentials{github: [cred1, cred2]}

      {:ok, result} = Credentials.get(creds, :github)
      assert result in [cred1, cred2]
    end

    test "rotation cycles through credentials" do
      cred1 = %{source: :env, token: "token-1"}
      cred2 = %{source: :cli, token: "token-2"}
      creds = %Credentials{github: [cred1, cred2]}

      # Call get multiple times — should rotate
      results =
        for _ <- 1..4 do
          {:ok, cred} = Credentials.get(creds, :github)
          cred.token
        end

      # Should see both tokens across multiple calls
      assert "token-1" in results
      assert "token-2" in results
    end

    test "returns error for unknown platform" do
      creds = Credentials.load()
      assert {:error, :no_credentials} = Credentials.get(creds, :nonexistent)
    end
  end

  describe "gh_auth_token/1" do
    test "returns the trimmed token when gh exits 0" do
      cmd = fn "gh", ["auth", "token"], _opts -> {"ghp_x\n", 0} end
      assert Credentials.gh_auth_token(cmd) == "ghp_x"
    end

    test "returns nil when gh is not logged in" do
      cmd = fn _, _, _ -> {"no oauth token\n", 1} end
      assert Credentials.gh_auth_token(cmd) == nil
    end

    test "returns nil on an empty token" do
      assert Credentials.gh_auth_token(fn _, _, _ -> {"\n", 0} end) == nil
    end

    test "returns nil when gh is not installed" do
      cmd = fn _, _, _ -> raise ErlangError, original: :enoent end
      assert Credentials.gh_auth_token(cmd) == nil
    end
  end
end
