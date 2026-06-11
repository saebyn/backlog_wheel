defmodule BacklogWheel.Repo.Migrations.RenameBoostTotalSnapshotKey do
  use Ecto.Migration

  def up do
    rename_snapshot_entry_key("boost_total", "channel_point_vote_total")
  end

  def down do
    rename_snapshot_entry_key("channel_point_vote_total", "boost_total")
  end

  defp rename_snapshot_entry_key(from_key, to_key) do
    repo = repo()

    %{rows: rows} = repo.query!("select id, snapshot from spins where snapshot is not null", [])

    Enum.each(rows, fn [id, snapshot] ->
      snapshot = if is_binary(snapshot), do: Jason.decode!(snapshot), else: snapshot
      updated_snapshot = update_entries(snapshot, from_key, to_key)

      if updated_snapshot != snapshot do
        repo.query!("update spins set snapshot = ? where id = ?", [
          Jason.encode!(updated_snapshot),
          id
        ])
      end
    end)
  end

  defp update_entries(%{"entries" => entries} = snapshot, from_key, to_key)
       when is_list(entries) do
    entries = Enum.map(entries, &rename_key(&1, from_key, to_key))
    Map.put(snapshot, "entries", entries)
  end

  defp update_entries(snapshot, _from_key, _to_key), do: snapshot

  defp rename_key(%{} = entry, from_key, to_key) do
    case Map.fetch(entry, from_key) do
      {:ok, value} ->
        entry
        |> Map.delete(from_key)
        |> Map.put(to_key, value)

      :error ->
        entry
    end
  end

  defp rename_key(entry, _from_key, _to_key), do: entry
end
