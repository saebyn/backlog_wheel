defmodule BacklogWheelWeb.DateTimeHelpers do
  @moduledoc """
  Formatting helpers for date/time values shown in the UI.
  """

  def format_local_datetime(nil), do: "Never"

  def format_local_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_unix(:second)
    |> :calendar.system_time_to_local_time(:second)
    |> NaiveDateTime.from_erl!()
    |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  def format_datetime_with_age(nil), do: "Never"

  def format_datetime_with_age(%DateTime{} = datetime) do
    "#{format_local_datetime(datetime)} (#{format_time_ago(datetime)} ago)"
  end

  def format_utc_datetime(nil), do: "Never"

  def format_utc_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  def format_time_ago(%DateTime{} = datetime) do
    seconds = max(DateTime.diff(DateTime.utc_now(), datetime, :second), 0)

    cond do
      seconds < 60 ->
        "just now"

      seconds < 3_600 ->
        "#{div(seconds, 60)}m"

      seconds < 86_400 ->
        "#{div(seconds, 3_600)}h"

      true ->
        days = div(seconds, 86_400)
        years = div(days, 365)
        remaining_days = rem(days, 365)

        if years > 0 do
          "#{years}y #{remaining_days}d"
        else
          "#{days}d"
        end
    end
  end
end
