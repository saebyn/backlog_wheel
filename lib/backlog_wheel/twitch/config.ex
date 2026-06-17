defmodule BacklogWheel.Twitch.Config do
  @moduledoc """
  Twitch integration configuration.

  App-level OAuth client values are merged with community-level channel settings.
  """

  @enforce_keys [:client_id, :client_secret, :broadcaster_id, :reward_cost]
  defstruct [
    :client_id,
    :client_secret,
    :broadcaster_id,
    :reward_cost,
    :eventsub_secret,
    :eventsub_callback_url
  ]

  @type t :: %__MODULE__{
          client_id: String.t(),
          client_secret: String.t(),
          broadcaster_id: String.t(),
          reward_cost: pos_integer(),
          eventsub_secret: String.t() | nil,
          eventsub_callback_url: String.t() | nil
        }

  @required_keys [:client_id, :client_secret, :broadcaster_id]
  @oauth_required_keys [:client_id, :client_secret]

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, {:missing_config, [atom()]}}
  def new(
        config \\ Application.get_env(:backlog_wheel, :twitch, []),
        required_keys \\ @required_keys
      ) do
    twitch_config = %__MODULE__{
      client_id: value(config, :client_id),
      client_secret: value(config, :client_secret),
      broadcaster_id: value(config, :broadcaster_id),
      reward_cost: reward_cost(config),
      eventsub_secret: value(config, :eventsub_secret),
      eventsub_callback_url: value(config, :eventsub_callback_url)
    }

    case missing_keys(twitch_config, required_keys) do
      [] -> {:ok, twitch_config}
      missing -> {:error, {:missing_config, missing}}
    end
  end

  @spec oauth(keyword() | map()) :: {:ok, t()} | {:error, {:missing_config, [atom()]}}
  def oauth(config \\ Application.get_env(:backlog_wheel, :twitch, [])) do
    new(config, @oauth_required_keys)
  end

  @spec configured?(keyword() | map()) :: boolean()
  def configured?(config \\ Application.get_env(:backlog_wheel, :twitch, [])) do
    match?({:ok, %__MODULE__{}}, new(config))
  end

  defp missing_keys(config, required_keys) do
    Enum.filter(required_keys, fn key -> blank?(Map.fetch!(config, key)) end)
  end

  defp value(config, key) when is_list(config), do: Keyword.get(config, key)

  defp value(config, key) when is_map(config),
    do: Map.get(config, key) || Map.get(config, Atom.to_string(key))

  defp value(_config, _key), do: nil

  defp reward_cost(config) do
    case value(config, :reward_cost) do
      value when is_integer(value) and value > 0 -> value
      value when is_binary(value) -> parse_reward_cost(value)
      _value -> 100
    end
  end

  defp parse_reward_cost(value) do
    case Integer.parse(value) do
      {cost, ""} when cost > 0 -> cost
      _invalid -> 100
    end
  end

  defp blank?(value), do: value in [nil, ""]
end
