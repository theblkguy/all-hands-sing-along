defmodule AllHandsSingAlongWeb.HealthController do
  @moduledoc """
  Liveness endpoint for Fly.io HTTP checks. Kept off the SSL redirect list.
  """
  use AllHandsSingAlongWeb, :controller

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end
end
