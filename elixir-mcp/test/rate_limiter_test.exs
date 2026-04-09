# SPDX-License-Identifier: PMPL-1.0-or-later
# Unit tests for FeedbackATron.RateLimiter.

defmodule FeedbackATron.RateLimiterTest do
  use ExUnit.Case, async: false

  alias FeedbackATron.RateLimiter

  setup do
    case Process.whereis(RateLimiter) do
      nil -> {:ok, _} = RateLimiter.start_link([])
      _pid -> :ok
    end

    # Reset all platforms before each test
    for platform <- [:github, :gitlab, :bitbucket, :codeberg, :bugzilla, :email] do
      RateLimiter.reset(platform)
    end

    :ok
  end

  describe "check/1" do
    test "allows first request to any platform" do
      assert :ok = RateLimiter.check(:github)
    end

    test "allows requests within limits" do
      assert :ok = RateLimiter.check(:github)
      assert :ok = RateLimiter.check(:gitlab)
    end
  end

  describe "acquire/1" do
    test "allows and records first request" do
      assert :ok = RateLimiter.acquire(:github)
    end

    test "enforces cooldown between rapid requests" do
      assert :ok = RateLimiter.acquire(:github)
      # Immediate second request should be rate limited (cooldown)
      result = RateLimiter.acquire(:github)
      assert {:error, %FeedbackATron.Error.RateLimitError{platform: :github}} = result
    end
  end

  describe "status/1" do
    test "returns status map with expected fields" do
      status = RateLimiter.status(:github)
      assert is_map(status)
      assert Map.has_key?(status, :platform)
      assert Map.has_key?(status, :used)
      assert Map.has_key?(status, :max)
      assert Map.has_key?(status, :remaining)
    end

    test "starts with zero used" do
      status = RateLimiter.status(:github)
      assert status.used == 0
      assert status.remaining == status.max
    end

    test "used increments after acquire" do
      RateLimiter.acquire(:codeberg)
      status = RateLimiter.status(:codeberg)
      assert status.used == 1
    end
  end

  describe "reset/1" do
    test "resets used count to zero" do
      RateLimiter.acquire(:bitbucket)
      RateLimiter.reset(:bitbucket)
      status = RateLimiter.status(:bitbucket)
      assert status.used == 0
    end

    test "allows requests after reset" do
      RateLimiter.acquire(:gitlab)
      RateLimiter.reset(:gitlab)
      assert :ok = RateLimiter.acquire(:gitlab)
    end
  end
end
