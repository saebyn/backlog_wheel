defmodule BacklogWheel.Repo do
  use Ecto.Repo,
    otp_app: :backlog_wheel,
    adapter: Ecto.Adapters.Postgres
end
