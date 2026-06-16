defmodule BacklogWheelWeb.SpinRecapLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <section id="spin-recap-page" class="space-y-6">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <.header>
            Spin Recap
            <:subtitle>Snapshot of the wheel when the winning game was selected.</:subtitle>
          </.header>

          <.link id="spin-recap-history-link" navigate={~p"/history"} class="btn btn-ghost">
            Back to History
          </.link>
        </div>

        <section
          id={"spin-recap-winner-#{@spin.id}"}
          class="overflow-hidden rounded-[2rem] border border-primary/20 bg-base-100 shadow-xl"
        >
          <div class="h-2 bg-gradient-to-r from-orange-500 via-fuchsia-500 to-cyan-400"></div>
          <div class="grid gap-6 p-6 md:grid-cols-[10rem_1fr] md:items-center">
            <div class="flex size-36 items-center justify-center overflow-hidden rounded-3xl border border-base-300 bg-base-200 shadow-lg">
              <img
                :if={@spin.game.image_url}
                src={@spin.game.image_url}
                alt={@spin.game.title}
                class="h-full w-full object-cover"
              />
              <.icon :if={!@spin.game.image_url} name="hero-trophy" class="size-16 text-primary" />
            </div>

            <div>
              <p class="text-sm font-black uppercase tracking-[0.35em] text-primary">Winner</p>
              <h1 class="mt-2 text-4xl font-black tracking-tight sm:text-5xl">{@spin.game.title}</h1>
              <p class="mt-3 text-base-content/70">
                Spun
                <span title={format_utc_datetime(@spin.spun_at)}>
                  {format_datetime_with_age(@spin.spun_at)}
                </span>
                · {@spin.source}
              </p>
              <p
                :if={@spin.voting_session}
                id="spin-recap-session"
                class="mt-2 text-sm text-base-content/60"
              >
                Voting session: {@spin.voting_session.title || "Session #{@spin.voting_session.id}"}
              </p>
            </div>
          </div>
        </section>

        <section id="spin-recap-summary" class="grid gap-3 sm:grid-cols-3">
          <div class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
            <p class="text-xs font-bold uppercase tracking-[0.2em] text-base-content/50">
              Winner Odds
            </p>
            <p class="mt-2 text-3xl font-black text-primary">{@winner_odds_percent}%</p>
          </div>
          <div class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
            <p class="text-xs font-bold uppercase tracking-[0.2em] text-base-content/50">
              Final Weight
            </p>
            <p class="mt-2 text-3xl font-black">{@winner_weight} / {@total_weight}</p>
          </div>
          <div class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
            <p class="text-xs font-bold uppercase tracking-[0.2em] text-base-content/50">Spin Time</p>
            <p class="mt-2 text-lg font-bold" title={format_utc_datetime(@spin.spun_at)}>
              {format_local_datetime(@spin.spun_at)}
            </p>
          </div>
        </section>

        <section
          id="spin-recap-pool"
          class="rounded-[2rem] border border-base-300 bg-base-100 p-5 shadow-sm"
        >
          <div class="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h2 class="text-2xl font-black">Final Wheel Pool</h2>
              <p class="text-sm text-base-content/60">
                Final weights combine starting votes and channel point votes.
              </p>
            </div>
            <p class="text-sm font-semibold text-base-content/60">{@entry_count} games</p>
          </div>

          <p
            :if={!@snapshot_available?}
            id="spin-recap-missing-snapshot"
            class="mt-4 rounded-2xl bg-warning/10 p-4 text-sm text-base-content/70"
          >
            Detailed wheel snapshot data is unavailable for this older spin, so only the recorded winner and timestamp can be shown.
          </p>

          <div :if={@snapshot_available?} id="spin-recap-entries" class="mt-5 space-y-3">
            <div
              :for={entry <- @entries}
              id={"spin-recap-entry-#{entry.game_id}"}
              class={entry_card_class(entry.winner?)}
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="font-bold leading-tight">{entry.title}</p>
                  <p class="mt-1 text-xs text-base-content/60">
                    Starting votes {entry.base_weight} + channel point votes {entry.channel_point_vote_total}
                  </p>
                </div>
                <div class="text-right">
                  <p class="text-xl font-black">{entry.final_weight}</p>
                  <p class="text-xs font-semibold text-base-content/60">{entry.odds_percent}%</p>
                </div>
              </div>
              <div class="mt-3 h-2 overflow-hidden rounded-full bg-base-300">
                <div class="h-full rounded-full bg-primary" style={"width: #{entry.odds_percent}%"}>
                </div>
              </div>
            </div>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    spin = Backlog.get_spin!(socket.assigns.current_community, id)
    entries = snapshot_entries(spin)
    total_weight = snapshot_total_weight(spin, entries)

    entries =
      Enum.map(entries, &Map.put(&1, :odds_percent, odds_percent(&1.final_weight, total_weight)))

    winner_entry = Enum.find(entries, & &1.winner?)
    winner_weight = if winner_entry, do: winner_entry.final_weight, else: 0

    {:ok,
     socket
     |> assign(:page_title, "Spin Recap")
     |> assign(:spin, spin)
     |> assign(:entries, entries)
     |> assign(:entry_count, length(entries))
     |> assign(:snapshot_available?, entries != [])
     |> assign(:total_weight, total_weight)
     |> assign(:winner_weight, winner_weight)
     |> assign(:winner_odds_percent, odds_percent(winner_weight, total_weight))}
  end

  defp snapshot_entries(%{
         snapshot: %{"entries" => entries, "winning_game_id" => winning_game_id}
       })
       when is_list(entries) do
    entries
    |> Enum.map(&normalize_snapshot_entry(&1, winning_game_id))
    |> Enum.sort_by(& &1.final_weight, :desc)
  end

  defp snapshot_entries(_spin), do: []

  defp normalize_snapshot_entry(entry, winning_game_id) do
    final_weight = number_value(entry["final_weight"])
    base_weight = number_value(entry["base_weight"])
    channel_point_vote_total = number_value(entry["channel_point_vote_total"])

    %{
      game_id: entry["game_id"],
      title: entry["title"] || "Untitled game",
      base_weight: base_weight,
      channel_point_vote_total: channel_point_vote_total,
      final_weight: final_weight,
      winner?: entry["game_id"] == winning_game_id,
      odds_percent: "0.0"
    }
  end

  defp snapshot_total_weight(%{snapshot: %{"total_weight" => total_weight}}, _entries)
       when is_number(total_weight),
       do: total_weight

  defp snapshot_total_weight(_spin, entries), do: Enum.reduce(entries, 0, &(&1.final_weight + &2))

  defp odds_percent(_weight, 0), do: "0.0"

  defp odds_percent(weight, total_weight) do
    (weight / total_weight * 100)
    |> :erlang.float_to_binary(decimals: 1)
  end

  defp entry_card_class(true) do
    "rounded-2xl border border-primary/40 bg-primary/10 p-4 shadow-sm ring-1 ring-primary/20"
  end

  defp entry_card_class(false), do: "rounded-2xl border border-base-300 bg-base-200 p-4"

  defp number_value(value) when is_number(value), do: value
  defp number_value(_value), do: 0
end
