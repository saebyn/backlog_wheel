defmodule BacklogWheel.Twitch.ConfigTest do
  use ExUnit.Case, async: true

  alias BacklogWheel.Twitch.Config

  test "new/1 returns config when all Twitch values are present" do
    assert {:ok,
            %Config{
              client_id: "client-id",
              client_secret: "client-secret",
              broadcaster_id: "broadcaster-id"
            }} =
             Config.new(%{
               "client_id" => "client-id",
               "client_secret" => "client-secret",
               "broadcaster_id" => "broadcaster-id"
             })
  end

  test "new/1 reports missing Twitch values" do
    assert Config.new(client_id: "", client_secret: "client-secret") ==
             {:error, {:missing_config, [:client_id, :broadcaster_id]}}
  end

  test "configured?/1 is false unless every Twitch value is present" do
    refute Config.configured?(client_id: "client-id")

    assert Config.configured?(
             client_id: "client-id",
             client_secret: "client-secret",
             broadcaster_id: "broadcaster-id"
           )
  end
end
