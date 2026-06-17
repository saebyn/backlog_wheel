defmodule BacklogWheel.Discord do
  @moduledoc """
  Discord OAuth integration helpers.
  """

  alias BacklogWheel.Discord.Config

  @spec config() :: {:ok, Config.t()} | {:error, {:missing_config, [atom()]}}
  def config, do: Config.new()

  @spec configured?() :: boolean()
  def configured?, do: match?({:ok, _config}, config())

  @spec client() :: module()
  def client,
    do: Application.get_env(:backlog_wheel, :discord_client, BacklogWheel.Discord.Client)

  @spec redirect_uri(Plug.Conn.t()) :: String.t()
  def redirect_uri(conn) do
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"

    "#{conn.scheme}://#{conn.host}#{port}/auth/discord/callback"
  end
end
