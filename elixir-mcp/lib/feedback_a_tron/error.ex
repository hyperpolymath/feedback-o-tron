# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.Error do
  @moduledoc """
  Structured error types for feedback submission operations.

  Provides specific, actionable error information instead of generic
  `:error` tuples, making it easier for AI agents to diagnose and
  recover from failures.
  """

  @type t ::
          %__MODULE__.AuthenticationError{}
          | %__MODULE__.RateLimitError{}
          | %__MODULE__.NetworkError{}
          | %__MODULE__.ValidationError{}
          | %__MODULE__.PlatformError{}
          | %__MODULE__.DuplicateError{}

  defmodule AuthenticationError do
    @moduledoc "Credentials are missing, expired, or rejected by the platform."
    defexception [:platform, :reason, :message]

    @impl true
    def message(%{platform: platform, reason: reason}) do
      "Authentication failed for #{platform}: #{reason}"
    end
  end

  defmodule RateLimitError do
    @moduledoc "Platform rate limit has been reached."
    defexception [:platform, :resets_at, :remaining, :message]

    @impl true
    def message(%{platform: platform, resets_at: resets_at}) do
      "Rate limited on #{platform}, resets at #{resets_at}"
    end
  end

  defmodule NetworkError do
    @moduledoc "Network-level failure (DNS, TLS, timeout, connection refused)."
    defexception [:platform, :reason, :url, :message]

    @impl true
    def message(%{platform: platform, reason: reason}) do
      "Network error for #{platform}: #{reason}"
    end
  end

  defmodule ValidationError do
    @moduledoc "Issue payload failed validation (missing fields, bad format)."
    defexception [:field, :reason, :message]

    @impl true
    def message(%{field: field, reason: reason}) do
      "Validation error on #{field}: #{reason}"
    end
  end

  defmodule PlatformError do
    @moduledoc "Platform returned an unexpected HTTP status or response."
    defexception [:platform, :status, :body, :message]

    @impl true
    def message(%{platform: platform, status: status}) do
      "Platform #{platform} returned HTTP #{status}"
    end
  end

  defmodule DuplicateError do
    @moduledoc "Issue was identified as a duplicate of an existing submission."
    defexception [:existing_hash, :similarity, :message]

    @impl true
    def message(%{existing_hash: hash, similarity: sim}) do
      "Duplicate detected (hash: #{hash}, similarity: #{sim})"
    end
  end
end
