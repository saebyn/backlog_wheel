defmodule BacklogWheelWeb.SpinHistoryLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Spin History
        <:subtitle>Recent wheel results, newest first.</:subtitle>
        <:actions>
          <.button navigate={~p"/wheel"} variant="primary">Open Wheel</.button>
        </:actions>
      </.header>

      <section id="spin-history-page" class="space-y-3">
        <p
          :if={@spins == []}
          id="empty-spin-history"
          class="rounded-2xl bg-base-200 p-6 text-base-content/70"
        >
          No spins recorded yet.
        </p>

        <div
          :for={spin <- @spins}
          id={"history-spin-#{spin.id}"}
          class="flex items-center gap-4 rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm"
        >
          <div class="flex size-16 shrink-0 items-center justify-center overflow-hidden rounded-2xl border border-base-300 bg-base-200">
            <img
              :if={spin.game.image_url}
              src={spin.game.image_url}
              alt={spin.game.title}
              class="h-full w-full object-cover"
            />
            <.icon :if={!spin.game.image_url} name="hero-trophy" class="size-8 text-primary" />
          </div>

          <div class="min-w-0 flex-1">
            <.link navigate={~p"/games/#{spin.game}"} class="text-lg font-bold hover:underline">
              {spin.game.title}
            </.link>
            <p class="mt-1 text-sm text-base-content/60">
              <span title={format_utc_datetime(spin.spun_at)}>
                {format_datetime_with_age(spin.spun_at)}
              </span>
              · {spin.source}
            </p>
            <div
              :if={winner_snapshot_entry(spin)}
              id={"spin-snapshot-summary-#{spin.id}"}
              class="mt-3 rounded-xl bg-base-200 p-3 text-sm"
            >
              <% winner_entry = winner_snapshot_entry(spin) %>
              <% total_weight = snapshot_total_weight(spin) %>
              <p class="font-semibold text-base-content/80">
                Winner votes: {winner_entry["final_weight"]} of {total_weight} ({winner_odds_percent(
                  winner_entry,
                  total_weight
                )}%)
              </p>
              <p class="mt-1 text-xs text-base-content/60">
                Starting votes {winner_entry["base_weight"]} + channel point votes {winner_entry[
                  "channel_point_vote_total"
                ]} · {snapshot_entry_count(spin)} entries snapshotted
              </p>
            </div>
          </div>

          <.link
            id={"delete-spin-#{spin.id}"}
            phx-click="delete_spin"
            phx-value-id={spin.id}
            data-confirm="Delete this spin history entry?"
            class="btn btn-ghost btn-sm text-error"
          >
            Delete
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Spin History")
     |> refresh_spins()}
  end

  @impl true
  def handle_event("delete_spin", %{"id" => id}, socket) do
    spin = Backlog.get_spin!(id)
    {:ok, _spin} = Backlog.delete_spin(spin)

    {:noreply, refresh_spins(socket)}
  end

  defp refresh_spins(socket) do
    assign(socket, :spins, Backlog.list_recent_spins(100))
  end

  defp winner_snapshot_entry(%{
         snapshot: %{"entries" => entries, "winning_game_id" => winning_game_id}
       })
       when is_list(entries) do
    Enum.find(entries, &(&1["game_id"] == winning_game_id))
  end

  defp winner_snapshot_entry(_spin), do: nil

  defp snapshot_total_weight(%{snapshot: %{"total_weight" => total_weight}}), do: total_weight
  defp snapshot_total_weight(_spin), do: 0

  defp snapshot_entry_count(%{snapshot: %{"entries" => entries}}) when is_list(entries),
    do: length(entries)

  defp snapshot_entry_count(_spin), do: 0

  defp winner_odds_percent(_winner_entry, 0), do: "0.0"

  defp winner_odds_percent(winner_entry, total_weight) do
    (winner_entry["final_weight"] / total_weight * 100)
    |> :erlang.float_to_binary(decimals: 1)
  end
end
