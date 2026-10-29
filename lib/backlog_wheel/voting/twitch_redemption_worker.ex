defmodule BacklogWheel.Voting.TwitchRedemptionWorker do
  @moduledoc false
  use GenServer
  require Logger

  alias BacklogWheel.Voting.TwitchRedemptions

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    schedule_reconciliation()
    {:ok, %{}}
  end

  def handle_info(:reconcile, state) do
    try do
      TwitchRedemptions.reconcile_rewards()
    rescue
      error ->
        Logger.error(
          "Twitch redemption reconciliation failed: #{Exception.format(:error, error, __STACKTRACE__)}"
        )
    end

    schedule_reconciliation()
    {:noreply, state}
  end

  @impl true
  def handle_info(:process, state) do
    try do
      TwitchRedemptions.process_pending()
      BacklogWheel.Voting.cleanup_finished_twitch_rewards()
    rescue
      error ->
        Logger.error(
          "Twitch redemption retry failed: #{Exception.format(:error, error, __STACKTRACE__)}"
        )
    end

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :process, :timer.seconds(15))
  defp schedule_reconciliation, do: Process.send_after(self(), :reconcile, :timer.seconds(60))
end
