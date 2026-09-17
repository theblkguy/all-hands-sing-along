# test/all_hands_sing_along_web/controllers/host_link_test.exs
defmodule AllHandsSingAlongWeb.HostLinkTest do
  use AllHandsSingAlongWeb.ConnCase

  alias AllHandsSingAlong.Rooms

  test "the host link grants host in a fresh browser", %{conn: conn} do
    {:ok, room} = Rooms.create_room()

    conn = get(conn, ~p"/rooms/#{room.code}/host/#{room.host_token}")

    assert redirected_to(conn) == ~p"/rooms/#{room.code}"
    assert get_session(conn, :host_tokens)[room.code] == room.host_token
    assert get_session(conn, :display_name) == "Host"
  end

  test "the host link keeps an existing display name", %{conn: conn} do
    {:ok, room} = Rooms.create_room()

    conn =
      conn
      |> init_test_session(%{"display_name" => "Ada", "guest_id" => "ada"})
      |> get(~p"/rooms/#{room.code}/host/#{room.host_token}")

    assert get_session(conn, :display_name) == "Ada"
    assert get_session(conn, :host_tokens)[room.code] == room.host_token
  end

  test "a wrong token is rejected", %{conn: conn} do
    {:ok, room} = Rooms.create_room()

    conn = get(conn, ~p"/rooms/#{room.code}/host/not-the-token")

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :host_tokens) in [nil, %{}]
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "host link"
  end

  test "the room page reveals the host link only to the host", %{conn: conn} do
    {:ok, room} = Rooms.create_room()

    host_conn =
      init_test_session(conn, %{
        "display_name" => "Ada",
        "guest_id" => "host-ada",
        "host_tokens" => %{room.code => room.host_token}
      })

    {:ok, view, _html} = live(host_conn, ~p"/rooms/#{room.code}")
    assert has_element?(view, "#host-link-panel")
    refute render(view) =~ room.host_token

    view |> element("#reveal-host-link") |> render_click()
    assert has_element?(view, "#copy-host-link")
    assert render(view) =~ "/rooms/#{room.code}/host/#{room.host_token}"

    guest_conn =
      conn
      |> recycle()
      |> init_test_session(%{"display_name" => "Sam", "guest_id" => "sam"})

    {:ok, guest_view, _html} = live(guest_conn, ~p"/rooms/#{room.code}")
    refute has_element?(guest_view, "#host-link-panel")
  end
end
