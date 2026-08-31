# lib/all_hands_sing_along_web/controllers/session_controller.ex
defmodule AllHandsSingAlongWeb.SessionController do
  @moduledoc """
  Sets session cookies for host/guest join, then redirects into the room LiveView.
  """
  use AllHandsSingAlongWeb, :controller

  alias AllHandsSingAlong.Rooms
  alias AllHandsSingAlong.Rooms.SessionForm

  @spec create_host(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_host(conn, params) do
    changeset = SessionForm.host_changeset(params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, %{display_name: name}} ->
        case Rooms.create_room() do
          {:ok, room} ->
            conn
            |> put_guest_session(name)
            |> put_session(:host_tokens, Map.put(host_tokens(conn), room.code, room.host_token))
            |> redirect(to: ~p"/rooms/#{room.code}")

          {:error, :code_collision} ->
            conn
            |> put_flash(:error, "Could not create a room. Try again.")
            |> redirect(to: ~p"/")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Could not create a room. Try again.")
            |> redirect(to: ~p"/")
        end

      {:error, changeset} ->
        conn
        |> put_flash(:error, first_error(changeset))
        |> redirect(to: ~p"/")
    end
  end

  @spec join(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def join(conn, params) do
    changeset = SessionForm.join_changeset(params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, %{display_name: name, code: code}} ->
        case Rooms.get_room_by_code(code) do
          {:ok, room} ->
            conn
            |> put_guest_session(name)
            |> redirect(to: ~p"/rooms/#{room.code}")

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Room not found")
            |> redirect(to: ~p"/")
        end

      {:error, changeset} ->
        conn
        |> put_flash(:error, first_error(changeset))
        |> redirect(to: ~p"/")
    end
  end

  defp put_guest_session(conn, name) do
    conn
    |> put_session(:display_name, name)
    |> put_session(:guest_id, get_session(conn, :guest_id) || Ecto.UUID.generate())
  end

  defp host_tokens(conn), do: get_session(conn, :host_tokens) || %{}

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> List.first()
    |> case do
      nil -> "Invalid"
      msg -> msg
    end
  end
end
