# test/all_hands_sing_along_web/live/home_live_test.exs
defmodule AllHandsSingAlongWeb.HomeLiveTest do
  use AllHandsSingAlongWeb.ConnCase

  alias AllHandsSingAlong.Rooms

  test "renders create and join forms", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "All Hands Sing Song"
    assert html =~ "Host a room"
    assert html =~ "Join a room"
    assert html =~ "Zoom companion"
  end

  test "POST host session creates a room and stores the token", %{conn: conn} do
    conn = post(conn, ~p"/session/host", %{"display_name" => "Ada"})
    path = redirected_to(conn)
    assert path =~ "/rooms/"
    assert get_session(conn, :display_name) == "Ada"
    code = path |> String.split("/") |> List.last()
    tokens = get_session(conn, :host_tokens)
    assert is_binary(tokens[code])
    assert {:ok, room} = Rooms.get_room_by_code(code)
    assert room.host_token == tokens[code]
  end

  test "POST join session requires a real room", %{conn: conn} do
    conn = post(conn, ~p"/session/join", %{"display_name" => "Sam", "code" => "ZZZZZZ"})
    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Room not found"
  end

  test "POST join session enters an existing room", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    conn = post(conn, ~p"/session/join", %{"display_name" => "Sam", "code" => room.code})
    assert redirected_to(conn) == ~p"/rooms/#{room.code}"
    assert get_session(conn, :display_name) == "Sam"
    assert get_session(conn, :host_tokens) in [nil, %{}]
  end
end
