# lib/all_hands_sing_along_web/user_auth.ex
defmodule AllHandsSingAlongWeb.UserAuth do
  @moduledoc """
  Session plumbing for Google sign-in.

  Plugs for controllers and an `on_mount` hook for LiveViews. When Google auth
  isn't configured (dev, test), everything passes through and `current_user`
  is nil — the app behaves exactly as before.
  """
  use AllHandsSingAlongWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3, current_path: 1]

  alias AllHandsSingAlong.Accounts
  alias AllHandsSingAlong.Accounts.User
  alias AllHandsSingAlong.Auth.Google

  @session_key :user_id
  @return_to_key :user_return_to

  @spec required?() :: boolean()
  def required?, do: Google.enabled?()

  @spec username_ready?(User.t() | nil) :: boolean()
  def username_ready?(user), do: User.username?(user)

  # -- Plugs ------------------------------------------------------------------

  @doc "Loads `conn.assigns.current_user` from the session, or nil."
  def fetch_current_user(conn, _opts) do
    assign(conn, :current_user, Accounts.get_user(get_session(conn, @session_key)))
  end

  @doc "Sends signed-out visitors to Google, remembering where they were going."
  def require_authenticated_user(conn, _opts) do
    cond do
      not required?() ->
        conn

      match?(%User{}, conn.assigns[:current_user]) ->
        conn

      true ->
        conn
        |> maybe_store_return_to()
        |> redirect(to: ~p"/auth/google")
        |> halt()
    end
  end

  @doc "When auth is on, signed-in people need a username before rooms."
  def require_username(conn, _opts) do
    cond do
      not required?() ->
        conn

      username_ready?(conn.assigns[:current_user]) ->
        conn

      true ->
        conn
        |> put_flash(:error, "Pick a username to continue.")
        |> redirect(to: ~p"/")
        |> halt()
    end
  end

  @doc "Sign the user in: reset the session (fixation), keep return_to, set the id."
  @spec log_in_user(Plug.Conn.t(), User.t()) :: Plug.Conn.t()
  def log_in_user(conn, %User{} = user) do
    return_to = get_session(conn, @return_to_key)

    conn =
      conn
      |> configure_session(renew: true)
      |> clear_session()
      |> put_session(@session_key, user.id)
      |> put_session(:guest_id, "user-#{user.id}")
      |> maybe_put_display_name(user)

    if username_ready?(user) do
      redirect(conn, to: return_to || ~p"/")
    else
      conn
      |> maybe_keep_return_to(return_to)
      |> redirect(to: ~p"/")
    end
  end

  @spec log_out_user(Plug.Conn.t()) :: Plug.Conn.t()
  def log_out_user(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/")
  end

  defp maybe_put_display_name(conn, user) do
    case User.display_name(user) do
      nil -> conn
      name -> put_session(conn, :display_name, name)
    end
  end

  defp maybe_keep_return_to(conn, return_to) when is_binary(return_to) do
    put_session(conn, @return_to_key, return_to)
  end

  defp maybe_keep_return_to(conn, _), do: conn

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, @return_to_key, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  # -- LiveView ----------------------------------------------------------------

  @doc """
  `on_mount` hook. `:mount_current_user` just assigns; `:require_user` also
  redirects to sign-in when auth is on and nobody is signed in.
  `:require_username` also sends people home until they pick a username.
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, assign_current_user(socket, session)}
  end

  def on_mount(:require_user, _params, session, socket) do
    socket = assign_current_user(socket, session)

    cond do
      required?() and is_nil(socket.assigns.current_user) ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Sign in to continue.")
         |> Phoenix.LiveView.redirect(to: ~p"/auth/google")}

      required?() and not username_ready?(socket.assigns.current_user) ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Pick a username to continue.")
         |> Phoenix.LiveView.redirect(to: ~p"/")}

      true ->
        {:cont, socket}
    end
  end

  defp assign_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      Accounts.get_user(session[Atom.to_string(@session_key)])
    end)
  end
end
