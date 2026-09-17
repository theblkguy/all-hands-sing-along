# lib/all_hands_sing_along_web/controllers/auth_controller.ex
defmodule AllHandsSingAlongWeb.AuthController do
  @moduledoc """
  Google sign-in round trip.

      GET  /auth/google           → redirect to Google's consent screen
      GET  /auth/google/callback  → exchange code, upsert user, sign in
      DELETE /auth/logout         → clear the session
  """
  use AllHandsSingAlongWeb, :controller

  alias AllHandsSingAlong.Accounts
  alias AllHandsSingAlong.Auth.Google
  alias AllHandsSingAlongWeb.UserAuth

  @state_key :google_oauth_state

  @spec request(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def request(conn, _params) do
    if Google.enabled?() do
      state = Google.new_state()

      conn
      |> put_session(@state_key, state)
      |> redirect(external: Google.authorize_url(redirect_uri(), state))
    else
      conn
      |> put_flash(:error, "Google sign-in isn't configured on this server.")
      |> redirect(to: ~p"/")
    end
  end

  @spec callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def callback(conn, %{"code" => code, "state" => state} = _params)
      when is_binary(code) and is_binary(state) do
    expected = get_session(conn, @state_key)
    conn = delete_session(conn, @state_key)

    with true <- is_binary(expected) and Plug.Crypto.secure_compare(expected, state),
         {:ok, claims} <- Google.fetch_claims(code, redirect_uri()),
         {:ok, user} <- Accounts.upsert_from_google(claims) do
      conn
      |> UserAuth.log_in_user(user)
    else
      false -> fail(conn, "That sign-in link expired. Try again.")
      {:error, :domain_not_allowed} -> fail(conn, "Use your work Google account to sign in.")
      {:error, :email_unverified} -> fail(conn, "That Google account's email isn't verified.")
      {:error, _} -> fail(conn, "Google sign-in didn't go through. Try again.")
    end
  end

  # Google redirects back with ?error=access_denied when the user cancels.
  def callback(conn, %{"error" => _}), do: fail(conn, "Sign-in was cancelled.")
  def callback(conn, _params), do: fail(conn, "That sign-in link is incomplete.")

  @spec logout(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def logout(conn, _params), do: UserAuth.log_out_user(conn)

  defp redirect_uri, do: url(~p"/auth/google/callback")

  defp fail(conn, message) do
    conn
    |> delete_session(@state_key)
    |> put_flash(:error, message)
    |> redirect(to: ~p"/")
  end
end
