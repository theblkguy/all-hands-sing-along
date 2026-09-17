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

  @doc "Sign the user in: reset the session (fixation), keep return_to, set the id."
  @spec log_in_user(Plug.Conn.t(), User.t()) :: Plug.Conn.t()
  def log_in_user(conn, %User{} = user) do
    return_to = get_session(conn, @return_to_key)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(@session_key, user.id)
    |> put_session(:display_name, user.name)
    |> put_session(:guest_id, "user-#{user.id}")
    |> redirect(to: return_to || ~p"/")
  end

  @spec log_out_user(Plug.Conn.t()) :: Plug.Conn.t()
  def log_out_user(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, @return_to_key, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  # -- LiveView ----------------------------------------------------------------

  @doc """
  `on_mount` hook. `:mount_current_user` just assigns; `:require_user` also
  redirects to sign-in when auth is on and nobody is signed in.
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, assign_current_user(socket, session)}
  end

  def on_mount(:require_user, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if required?() and is_nil(socket.assigns.current_user) do
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Sign in to continue.")
       |> Phoenix.LiveView.redirect(to: ~p"/auth/google")}
    else
      {:cont, socket}
    end
  end

  defp assign_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      Accounts.get_user(session[Atom.to_string(@session_key)])
    end)
  end
end
