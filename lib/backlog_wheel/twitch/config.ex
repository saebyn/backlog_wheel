defmodule BacklogWheel.Twitch.Config do
  @moduledoc """
  Local Twitch integration configuration.

  This struct only describes configuration required by future Twitch API work.
  It does not perform OAuth, EventSub setup, or Twitch API calls.
  """

  @enforce_keys [:client_id, :client_secret, :broadcaster_id]
  defstruct [:client_id, :client_secret, :broadcaster_id]

  @type t :: %__MODULE__{
          client_id: String.t(),
          client_secret: String.t(),
          broadcaster_id: String.t()
        }

  @keys [:client_id, :client_secret, :broadcaster_id]

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, {:missing_config, [atom()]}}
  def new(config \\ Application.get_env(:backlog_wheel, :twitch, [])) do
    twitch_config = %__MODULE__{
      client_id: value(config, :client_id),
      client_secret: value(config, :client_secret),
      broadcaster_id: value(config, :broadcaster_id)
    }

    case missing_keys(twitch_config) do
      [] -> {:ok, twitch_config}
      missing -> {:error, {:missing_config, missing}}
    end
  end

  @spec configured?(keyword() | map()) :: boolean()
  def configured?(config \\ Application.get_env(:backlog_wheel, :twitch, [])) do
    match?({:ok, %__MODULE__{}}, new(config))
  end

  defp missing_keys(config) do
    Enum.filter(@keys, fn key -> blank?(Map.fetch!(config, key)) end)
  end

  defp value(config, key) when is_list(config), do: Keyword.get(config, key)

  defp value(config, key) when is_map(config),
    do: Map.get(config, key) || Map.get(config, Atom.to_string(key))

  defp value(_config, _key), do: nil

  defp blank?(value), do: value in [nil, ""]
end
