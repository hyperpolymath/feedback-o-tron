# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule FeedbackATron.Params do
  @moduledoc """
  Shared request-parameter parsing for the intake surfaces.

  Both the MCP tools (`FeedbackATron.MCP.Tools.*`) and the HTTP intake
  router (`FeedbackATron.HTTPIntake.Router`) accept the same wire
  arguments; this module keeps their interpretation identical so a
  cartridge can forward arguments to either surface unchanged.
  """

  @doc """
  Parse a list of platform name strings into platform atoms.

  Unknown platform names are dropped. `nil`, non-lists, and lists that
  contain no known platforms all fall back to `[:github]`.
  """
  def parse_platforms(nil), do: [:github]

  def parse_platforms(platforms) when is_list(platforms) do
    platforms
    |> Enum.map(&platform_atom/1)
    |> Enum.filter(& &1)
    |> case do
      [] -> [:github]
      list -> list
    end
  end

  def parse_platforms(_), do: [:github]

  defp platform_atom("github"), do: :github
  defp platform_atom("gitlab"), do: :gitlab
  defp platform_atom("bitbucket"), do: :bitbucket
  defp platform_atom("codeberg"), do: :codeberg
  defp platform_atom("bugzilla"), do: :bugzilla
  defp platform_atom("email"), do: :email
  defp platform_atom(_), do: nil
end
