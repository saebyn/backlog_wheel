defmodule BacklogWheel.Twitch do
  @moduledoc """
  Boundary for future Twitch integration work.

  This module intentionally exposes only local configuration status for now.
  OAuth, EventSub, reward creation, and live Twitch API calls are out of scope.
  """

  alias BacklogWheel.Twitch.Config
  alias BacklogWheel.Twitch.Credential
  alias BacklogWheel.Repo

  @spec configured?() :: boolean()
  def configured?, do: Config.configured?()

  @spec config() :: {:ok, Config.t()} | {:error, {:missing_config, [atom()]}}
  def config, do: Config.new()

  @spec client() :: module()
  def client, do: Application.get_env(:backlog_wheel, :twitch_client, BacklogWheel.Twitch.Client)

  @spec redirect_uri(Plug.Conn.t()) :: String.t()
  def redirect_uri(conn) do
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"

    "#{conn.scheme}://#{conn.host}#{port}/twitch/oauth/callback"
  end

  @spec get_credential() :: Credential.t() | nil
  def get_credential do
    Credential
    |> Ecto.Query.last(:inserted_at)
    |> Repo.one()
  end

  @spec credential_configured?() :: boolean()
  def credential_configured?, do: not is_nil(get_credential())

  @spec save_credential(map()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def save_credential(attrs) do
    case get_credential() do
      nil -> %Credential{}
      credential -> credential
    end
    |> Credential.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @spec delete_credential() :: :ok
  def delete_credential do
    Repo.delete_all(Credential)
    :ok
  end
end
