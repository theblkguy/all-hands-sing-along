# test/all_hands_sing_along_web/live/home_live_test.exs
defmodule AllHandsSingAlongWeb.HomeLiveTest do
  use AllHandsSingAlongWeb.ConnCase

  alias AllHandsSingAlong.Rooms

  test "renders create and join forms", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "All Hands Sing Song"
    assert html =~ "Host a room"
    assert html =~ "Join a room"
    assert html =~ "Karaoke night"
    assert has_element?(view, "#how-it-works")
    assert html =~ "How it works"
    assert html =~ "Host starts the song"
    # Test env uses the stub adapter, so the app is not in Mac-worker mode.
    assert has_element?(view, "#host-no-setup")
    refute has_element?(view, "#host-mac-setup")
    refute has_element?(view, "#copy-setup-brew")
    refute has_element?(view, "#copy-setup-clone")
    refute html =~ "https://github.com/theblkguy/all-hands-sing-along.git"
    refute html =~ "the README"
    assert has_element?(view, "#join-no-install")
    join = view |> element("#join-room-form") |> render()
    refute join =~ "Homebrew"
    refute join =~ "Demucs"
  end

  test "POST host session creates a room and stores the token", %{conn: conn} do
    conn = post(conn, ~p"/session/host", %{"host" => %{"display_name" => "Ada"}})
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
    conn =
      post(conn, ~p"/session/join", %{"join" => %{"display_name" => "Sam", "code" => "ZZZZZZ"}})

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Room not found"
  end

  test "POST join session enters an existing room", %{conn: conn} do
    {:ok, room} = Rooms.create_room()

    conn =
      post(conn, ~p"/session/join", %{"join" => %{"display_name" => "Sam", "code" => room.code}})

    assert redirected_to(conn) == ~p"/rooms/#{room.code}"
    assert get_session(conn, :display_name) == "Sam"
    assert get_session(conn, :host_tokens) in [nil, %{}]
  end

  test "POST host session requires a name", %{conn: conn} do
    conn = post(conn, ~p"/session/host", %{"host" => %{"display_name" => "  "}})
    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "display_name"
  end

  test "past rooms lists rooms the signed-in user was in", %{conn: conn} do
    user = AllHandsSingAlong.Fixtures.user_fixture(username: "ada")
    {:ok, room} = Rooms.create_room(user)

    conn = init_test_session(conn, %{"user_id" => user.id, "display_name" => "ada"})
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#past-rooms")
    assert has_element?(view, "#rejoin-#{room.code}")
    refute has_element?(view, "#create-room-form input[name='host[display_name]']")
  end
end
