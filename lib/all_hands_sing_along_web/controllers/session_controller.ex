# lib/all_hands_sing_along_web/controllers/session_controller.ex
defmodule AllHandsSingAlongWeb.SessionController do
  @moduledoc """
  Sets session cookies for host/guest join, then redirects into the room LiveView.
  """
  use AllHandsSingAlongWeb, :controller

  alias AllHandsSingAlong.Rooms

  @spec create_host(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_host(conn, params) do
    name = params |> Map.get("display_name", "") |> String.trim()

    if name == "" do
      conn
      |> put_flash(:error, "Name is required")
      |> redirect(to: ~p"/")
    else
      {:ok, room} = Rooms.create_room()

      conn
      |> put_guest_session(name)
      |> put_session(:host_tokens, Map.put(host_tokens(conn), room.code, room.host_token))
      |> redirect(to: ~p"/rooms/#{room.code}")
    end
  end

  @spec join(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def join(conn, params) do
    name = params |> Map.get("display_name", "") |> String.trim()
    code = params |> Map.get("code", "") |> String.trim()

    with true <- name != "",
         {:ok, room} <- Rooms.get_room_by_code(code) do
      conn
      |> put_guest_session(name)
      |> redirect(to: ~p"/rooms/#{room.code}")
    else
      false ->
        conn
        |> put_flash(:error, "Name is required")
        |> redirect(to: ~p"/")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Room not found")
        |> redirect(to: ~p"/")
    end
  end

  defp put_guest_session(conn, name) do
    conn
    |> put_session(:display_name, name)
    |> put_session(:guest_id, get_session(conn, :guest_id) || Ecto.UUID.generate())
  end

  defp host_tokens(conn), do: get_session(conn, :host_tokens) || %{}
end
