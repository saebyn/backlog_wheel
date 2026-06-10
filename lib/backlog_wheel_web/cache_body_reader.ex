defmodule BacklogWheelWeb.CacheBodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, cache_body(conn, body)}

      {:more, body, conn} ->
        {:more, body, cache_body(conn, body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cache_body(conn, body) do
    cached_body = [body | Map.get(conn.private, :raw_body, [])]
    Plug.Conn.put_private(conn, :raw_body, cached_body)
  end
end
