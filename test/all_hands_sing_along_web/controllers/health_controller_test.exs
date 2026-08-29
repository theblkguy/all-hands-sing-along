defmodule AllHandsSingAlongWeb.HealthControllerTest do
  use AllHandsSingAlongWeb.ConnCase, async: false

  test "GET /health returns ok", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert conn.status == 200
    assert conn.resp_body == "ok"
  end
end
