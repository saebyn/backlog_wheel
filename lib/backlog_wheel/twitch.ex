defmodule BacklogWheel.Twitch do
  @moduledoc """
  Boundary for future Twitch integration work.

  This module intentionally exposes only local configuration status for now.
  OAuth, EventSub, reward creation, and live Twitch API calls are out of scope.
  """

  alias BacklogWheel.Twitch.Config

  @spec configured?() :: boolean()
  def configured?, do: Config.configured?()

  @spec config() :: {:ok, Config.t()} | {:error, {:missing_config, [atom()]}}
  def config, do: Config.new()
end
