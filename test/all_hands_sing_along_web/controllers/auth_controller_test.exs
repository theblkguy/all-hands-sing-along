# test/all_hands_sing_along_web/controllers/auth_controller_test.exs
defmodule AllHandsSingAlongWeb.AuthControllerTest do
  use AllHandsSingAlongWeb.ConnCase

  alias AllHandsSingAlong.Accounts
  alias AllHandsSingAlong.Accounts.User
  alias AllHandsSingAlong.Auth.Google
  alias AllHandsSingAlong.Repo
  alias AllHandsSingAlong.Rooms

  @claims %{
    "sub" => "google-123",
    "email" => "ada@acme.com",
    "email_verified" => true,
    "name" => "Ada Lovelace",
    "picture" => "https://lh3.example/ada.png",
    "hd" => "acme.com"
  }

  setup do
    previous = Application.get_env(:all_hands_sing_along, Google, [])
    Application.put_env(:all_hands_sing_along, Google, Keyword.put(previous, :enabled, true))
    on_exit(fn -> Application.put_env(:all_hands_sing_along, Google, previous) end)
    :ok
  end

  defp stub_google(claims) do
    Req.Test.stub(Google, fn conn ->
      case conn.request_path do
        "/token" -> Req.Test.json(conn, %{"access_token" => "at-123", "token_type" => "Bearer"})
        "/v1/userinfo" -> Req.Test.json(conn, claims)
      end
    end)
  end

  defp allow_domains(domains) do
    current = Application.get_env(:all_hands_sing_along, Google, [])

    Application.put_env(
      :all_hands_sing_along,
      Google,
      Keyword.put(current, :allowed_domains, domains)
    )
  end

  defp sign_in_via_google(conn, claims) do
    stub_google(claims)
    conn = get(conn, ~p"/auth/google")
    state = get_session(conn, :google_oauth_state)
    assert is_binary(state)

    conn
    |> recycle()
    |> get(~p"/auth/google/callback?code=the-code&state=#{state}")
  end

  test "GET /auth/google redirects to Google with a state in the session", %{conn: conn} do
    conn = get(conn, ~p"/auth/google")
    location = redirected_to(conn, 302)
    assert location =~ "https://accounts.google.com/o/oauth2/v2/auth?"
    assert location =~ "client_id=test-client"
    assert location =~ URI.encode_www_form("/auth/google/callback")
    assert location =~ "state=" <> get_session(conn, :google_oauth_state)
  end

  test "callback signs the user in and creates the account", %{conn: conn} do
    conn = sign_in_via_google(conn, @claims)

    assert redirected_to(conn) == ~p"/"
    user = Repo.get_by!(User, google_sub: "google-123")
    assert user.email == "ada@acme.com"
    assert user.name == "Ada Lovelace"
    assert get_session(conn, :user_id) == user.id
    assert get_session(conn, :display_name) == "Ada Lovelace"
    assert get_session(conn, :google_oauth_state) == nil
  end

  test "signing in twice refreshes the same user", %{conn: conn} do
    sign_in_via_google(conn, @claims)
    sign_in_via_google(conn, Map.put(@claims, "name", "Ada L."))

    assert Repo.aggregate(User, :count) == 1
    assert Repo.get_by!(User, google_sub: "google-123").name == "Ada L."
  end

  test "callback rejects a bad state", %{conn: conn} do
    stub_google(@claims)
    conn = get(conn, ~p"/auth/google")

    conn =
      conn
      |> recycle()
      |> get(~p"/auth/google/callback?code=the-code&state=forged")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    assert get_session(conn, :user_id) == nil
    assert Repo.aggregate(User, :count) == 0
  end

  test "callback enforces the allowed domain", %{conn: conn} do
    allow_domains(["acme.com"])

    conn =
      sign_in_via_google(conn, %{
        @claims
        | "email" => "someone@gmail.com",
          "hd" => nil,
          "sub" => "google-999"
      })

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "work Google account"
    assert get_session(conn, :user_id) == nil
  end

  test "callback allows a matching Workspace domain", %{conn: conn} do
    allow_domains(["acme.com"])
    conn = sign_in_via_google(conn, @claims)
    assert is_integer(get_session(conn, :user_id))
  end

  test "callback handles the user cancelling", %{conn: conn} do
    conn = get(conn, ~p"/auth/google/callback?error=access_denied")
    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cancelled"
  end

  test "signing out clears the session", %{conn: conn} do
    conn = sign_in_via_google(conn, @claims)
    conn = conn |> recycle() |> delete(~p"/auth/logout")
    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_id) == nil
  end

  test "a signed-out visitor is sent to Google before a room", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    conn = get(conn, ~p"/rooms/#{room.code}")
    assert redirected_to(conn) == ~p"/auth/google"
    assert get_session(conn, :user_return_to) == "/rooms/#{room.code}"
  end

  test "after sign-in the visitor lands back on the room they wanted", %{conn: conn} do
    {:ok, room} = Rooms.create_room()
    conn = get(conn, ~p"/rooms/#{room.code}")
    conn = conn |> recycle() |> sign_in_via_google(@claims)
    assert redirected_to(conn) == ~p"/rooms/#{room.code}"
  end

  test "the home page shows Sign in when signed out and the forms when signed in", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#sign-in-google")
    refute has_element?(view, "#create-room-form")

    {:ok, user} = Accounts.upsert_from_google(@claims)
    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, html} = live(conn, ~p"/")
    refute has_element?(view, "#sign-in-google")
    assert has_element?(view, "#create-room-form")
    assert has_element?(view, "#user-chip")
    assert html =~ "Ada Lovelace"
  end

  test "the room owner is host from any browser, no cookie token needed", %{conn: conn} do
    {:ok, user} = Accounts.upsert_from_google(@claims)
    {:ok, room} = Rooms.create_room(user)
    assert room.host_user_id == user.id

    conn = init_test_session(conn, %{"user_id" => user.id, "display_name" => "Ada Lovelace"})
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.code}")
    assert has_element?(view, "#host-link-panel")

    {:ok, other} =
      Accounts.upsert_from_google(%{@claims | "sub" => "google-2", "email" => "b@acme.com"})

    other_conn =
      conn
      |> recycle()
      |> init_test_session(%{"user_id" => other.id, "display_name" => "Bea"})

    {:ok, other_view, _html} = live(other_conn, ~p"/rooms/#{room.code}")
    refute has_element?(other_view, "#host-link-panel")
  end

  test "POST /session/host attaches the room to the signed-in user", %{conn: conn} do
    {:ok, user} = Accounts.upsert_from_google(@claims)

    conn =
      conn
      |> init_test_session(%{"user_id" => user.id})
      |> post(~p"/session/host", %{"host" => %{"display_name" => "Ada"}})

    code = conn |> redirected_to() |> String.split("/") |> List.last()
    {:ok, room} = Rooms.get_room_by_code(code)
    assert room.host_user_id == user.id
    assert get_session(conn, :guest_id) == "user-#{user.id}"
  end
end
