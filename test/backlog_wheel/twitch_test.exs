defmodule BacklogWheel.TwitchTest do
  use ExUnit.Case, async: false

  alias BacklogWheel.Twitch
  alias BacklogWheel.Twitch.Config

  setup do
    original_config = Application.get_env(:backlog_wheel, :twitch)

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:backlog_wheel, :twitch)
      else
        Application.put_env(:backlog_wheel, :twitch, original_config)
      end
    end)
  end

  test "configured?/0 is false when local Twitch config is incomplete" do
    Application.put_env(:backlog_wheel, :twitch, client_id: "client-id")

    refute Twitch.configured?()
    assert Twitch.config() == {:error, {:missing_config, [:client_secret, :broadcaster_id]}}
  end

  test "config/0 returns local Twitch config when all values are present" do
    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret",
      broadcaster_id: "broadcaster-id"
    )

    assert Twitch.configured?()

    assert Twitch.config() ==
             {:ok,
              %Config{
                client_id: "client-id",
                client_secret: "client-secret",
                broadcaster_id: "broadcaster-id"
              }}
  end
end
