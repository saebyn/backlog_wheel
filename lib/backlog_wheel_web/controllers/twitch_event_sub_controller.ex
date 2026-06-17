defmodule BacklogWheelWeb.TwitchEventSubController do
  use BacklogWheelWeb, :controller

  require Logger

  alias BacklogWheel.Twitch
  alias BacklogWheel.Voting

  @redemption_add_type "channel.channel_points_custom_reward_redemption.add"

  def webhook(conn, params) do
    with {:ok, config} <- Twitch.eventsub_config(params),
         {:ok, secret} <- Twitch.eventsub_secret(config),
         :ok <- verify_signature(conn, secret) do
      handle_eventsub_message(conn, params)
    else
      {:error, {:missing_config, missing}} ->
        Logger.warning("Twitch EventSub webhook missing config: #{inspect(missing)}")
        send_resp(conn, :service_unavailable, "")

      {:error, {:unknown_broadcaster, broadcaster_id}} ->
        Logger.warning("Twitch EventSub webhook unknown broadcaster: #{inspect(broadcaster_id)}")
        send_resp(conn, :service_unavailable, "")

      {:error, :invalid_signature} ->
        send_resp(conn, :forbidden, "")
    end
  end

  defp handle_eventsub_message(conn, %{"challenge" => challenge}) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(:ok, challenge)
  end

  defp handle_eventsub_message(conn, %{
         "subscription" => %{"type" => @redemption_add_type},
         "event" => event
       }) do
    case Voting.ingest_twitch_reward_redemption(event) do
      {:ok, _vote} ->
        send_resp(conn, :no_content, "")

      {:ignored, reason} ->
        Logger.info("Ignored Twitch reward redemption: #{inspect(reason)}")
        send_resp(conn, :no_content, "")

      {:error, reason} ->
        Logger.warning("Failed to ingest Twitch reward redemption: #{inspect(reason)}")
        send_resp(conn, :unprocessable_entity, "")
    end
  end

  defp handle_eventsub_message(conn, %{"subscription" => %{"type" => type}}) do
    Logger.info("Ignored Twitch EventSub message type: #{type}")
    send_resp(conn, :no_content, "")
  end

  defp handle_eventsub_message(conn, _params), do: send_resp(conn, :bad_request, "")

  defp verify_signature(conn, secret) do
    message_id = header(conn, "twitch-eventsub-message-id")
    timestamp = header(conn, "twitch-eventsub-message-timestamp")
    signature = header(conn, "twitch-eventsub-message-signature")
    expected_signature = eventsub_signature(secret, message_id, timestamp, raw_body(conn))

    if is_binary(signature) and byte_size(signature) == byte_size(expected_signature) and
         Plug.Crypto.secure_compare(signature, expected_signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp eventsub_signature(secret, message_id, timestamp, body) do
    digest = :crypto.mac(:hmac, :sha256, secret, message_id <> timestamp <> body)
    "sha256=" <> Base.encode16(digest, case: :lower)
  end

  defp raw_body(conn) do
    conn.private
    |> Map.get(:raw_body, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp header(conn, name) do
    conn
    |> get_req_header(name)
    |> List.first()
    |> case do
      nil -> ""
      value -> value
    end
  end
end
