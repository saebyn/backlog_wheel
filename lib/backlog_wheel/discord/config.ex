defmodule BacklogWheel.Discord.Config do
  @moduledoc """
  Discord OAuth configuration loaded from application environment.
  """

  @enforce_keys [:client_id, :client_secret]
  defstruct [:client_id, :client_secret]

  @type t :: %__MODULE__{client_id: String.t(), client_secret: String.t()}

  @spec new() :: {:ok, t()} | {:error, {:missing_config, [atom()]}}
  def new do
    config = Application.get_env(:backlog_wheel, :discord, [])

    missing =
      [:client_id, :client_secret]
      |> Enum.reject(&present?(Keyword.get(config, &1)))

    if missing == [] do
      {:ok,
       %__MODULE__{
         client_id: Keyword.fetch!(config, :client_id),
         client_secret: Keyword.fetch!(config, :client_secret)
       }}
    else
      {:error, {:missing_config, missing}}
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
end
