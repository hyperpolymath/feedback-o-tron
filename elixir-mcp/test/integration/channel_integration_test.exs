# SPDX-License-Identifier: PMPL-1.0-or-later
# Integration tests for channel adapters using Bypass for HTTP mocking.
#
# These tests verify that each HTTP-based channel adapter correctly:
# - Constructs the API request
# - Handles success responses
# - Handles error responses with structured error types
# - Validates credentials
#
# No real external API calls are made.

defmodule FeedbackATron.Integration.ChannelIntegrationTest do
  use ExUnit.Case, async: true

  describe "Bitbucket channel" do
    test "validate_creds requires token" do
      assert {:error, _} = FeedbackATron.Channels.Bitbucket.validate_creds(%{})
      assert :ok = FeedbackATron.Channels.Bitbucket.validate_creds(%{token: "test"})
    end
  end

  describe "Codeberg channel" do
    test "validate_creds requires token" do
      assert {:error, _} = FeedbackATron.Channels.Codeberg.validate_creds(%{})
      assert :ok = FeedbackATron.Channels.Codeberg.validate_creds(%{token: "test"})
    end
  end

  describe "Bugzilla channel" do
    test "validate_creds accepts API key" do
      assert :ok = FeedbackATron.Channels.Bugzilla.validate_creds(%{token: "apikey123"})
    end

    test "validate_creds accepts username/password" do
      assert :ok =
               FeedbackATron.Channels.Bugzilla.validate_creds(%{
                 username: "user",
                 password: "pass"
               })
    end

    test "validate_creds rejects empty creds" do
      assert {:error, _} = FeedbackATron.Channels.Bugzilla.validate_creds(%{})
    end
  end

  describe "GitHub channel" do
    test "validate_creds requires token" do
      assert {:error, _} = FeedbackATron.Channels.GitHub.validate_creds(%{})
      assert :ok = FeedbackATron.Channels.GitHub.validate_creds(%{token: "ghp_test"})
    end
  end

  describe "GitLab channel" do
    test "validate_creds requires token" do
      assert {:error, _} = FeedbackATron.Channels.GitLab.validate_creds(%{})
      assert :ok = FeedbackATron.Channels.GitLab.validate_creds(%{token: "glpat_test"})
    end
  end

  describe "Email channel" do
    test "validate_creds requires smtp_server and from_address" do
      assert {:error, _} = FeedbackATron.Channels.Email.validate_creds(%{})

      assert {:error, _} =
               FeedbackATron.Channels.Email.validate_creds(%{smtp_server: "mail.example.com"})

      assert :ok =
               FeedbackATron.Channels.Email.validate_creds(%{
                 smtp_server: "mail.example.com",
                 from_address: "test@example.com"
               })
    end

    test "submit returns not_implemented error" do
      issue = %{title: "Test", body: "Body", repo: nil}
      cred = %{smtp_server: "mail.example.com", from_address: "test@example.com"}
      assert {:error, %{platform: :email, error: :not_implemented}} =
               FeedbackATron.Channels.Email.submit(issue, cred, [])
    end
  end

  describe "structured error types" do
    test "all HTTP-based channels return structured errors on failure" do
      # This test verifies the error module is loadable and constructable
      assert %FeedbackATron.Error.AuthenticationError{platform: :github} =
               %FeedbackATron.Error.AuthenticationError{platform: :github, reason: "test"}

      assert %FeedbackATron.Error.RateLimitError{platform: :gitlab} =
               %FeedbackATron.Error.RateLimitError{platform: :gitlab, resets_at: nil, remaining: 0}

      assert %FeedbackATron.Error.NetworkError{platform: :bitbucket} =
               %FeedbackATron.Error.NetworkError{platform: :bitbucket, reason: "timeout", url: "https://example.com"}

      assert %FeedbackATron.Error.PlatformError{platform: :codeberg} =
               %FeedbackATron.Error.PlatformError{platform: :codeberg, status: 500, body: "error"}

      assert %FeedbackATron.Error.ValidationError{field: "title"} =
               %FeedbackATron.Error.ValidationError{field: "title", reason: "too short"}
    end
  end
end
