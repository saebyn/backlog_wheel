# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     BacklogWheel.Repo.insert!(%BacklogWheel.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

BacklogWheel.Communities.Community
|> BacklogWheel.Repo.all()
|> Enum.each(fn community ->
  {:ok, _formats} = BacklogWheel.Voting.ensure_default_wheel_formats(community)
end)
